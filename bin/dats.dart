#!/usr/bin/env dart

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:args/args.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart' as yaml;

void main(List<String> args) async {
  final results = _parser.parse(args);
  if (results.flag('help')) {
    io.stderr.writeln(_parser.usage);
    return;
  }

  final dartBin = results.option('dart-bin')!;
  final format = results.option('format');
  if (format != 'machine' && format != 'json') {
    io.stderr.writeln('Invalid format: $format');
    io.stderr.writeln(_parser.usage);
    io.exitCode = 1;
    return;
  }

  var output = results.option('output')!;

  // Support macros, i.e. {*} or {*:PARAMS}.
  output = output.replaceAllMapped(
    RegExp(r'{([^{}:]+)(?::([^{}]+))?}'),
    (match) {
      final macro = match.group(1);
      final params = match.group(2);
      switch (macro) {
        case 'DATE':
          final format = params ?? 'yyyy_MM_dd';
          return DateFormat(format).format(DateTime.now());
        case 'EXT':
          return format == 'json' ? 'json' : 'txt';
        default:
          return match.group(0)!;
      }
    },
  );

  // Support arbitrary trailing options to `dart analyze`.
  final trailing = results.rest.join(' ');

  // Build up a command.
  final command = [
    dartBin,
    'analyze',
    '--no-fatal-warnings',
    '--format=$format',
    if (trailing.isNotEmpty) trailing,
    if (trailing.isEmpty) '.',
  ];

  // Support dry-run.
  if (results.flag('dry-run')) {
    io.stdout.writeln('${command.join(' ')} > $output');
    return;
  }

  // Create the directory if it doesn't exist.
  io.Directory(p.dirname(output)).createSync(recursive: true);

  // Run the command.
  final bool willPatch;
  var patchFile = io.File(results.option('patch')!);
  if (results.wasParsed('patch')) {
    if (!patchFile.existsSync()) {
      io.stderr.writeln('Patch file does not exist: $patchFile');
      io.exitCode = 1;
      return;
    }
    willPatch = true;
  } else {
    willPatch = patchFile.existsSync();
  }

  // If we're patching, `analysis_options.yaml` file must exist.
  final analysisOptions = io.File('analysis_options.yaml');
  if (willPatch && !analysisOptions.existsSync()) {
    io.stderr.writeln(
      'analysis_options.yaml does not exist, so it cannot be patched',
    );
    io.exitCode = 1;
    return;
  }

  late io.Directory tmpDir;
  late io.File tmpAnalysisOptions;
  if (willPatch) {
    tmpDir = io.Directory.systemTemp.createTempSync('dats');
  }

  try {
    // If we're patching, make a temporary copy of the analysis options.
    if (willPatch) {
      tmpAnalysisOptions = analysisOptions.copySync(
        p.join(tmpDir.path, 'analysis_options.yaml'),
      );

      final patches = await _patch(analysisOptions, patch: patchFile);
      if (patches > 0) {
        io.stderr.writeln('Patched $patches values into analysis_options.yaml');
      }
    }

    await _analyze(command, output: output);
  } finally {
    if (willPatch) {
      // Restore the original analysis options.
      tmpAnalysisOptions.copySync(analysisOptions.path);
      tmpDir.deleteSync(recursive: true);
    }
  }
}

Future<void> _analyze(List<String> command, {required String output}) async {
  // Actually run the command and capture stdout/stderr.
  final process = await io.Process.start(
    command.first,
    command.skip(1).toList(),
  );

  // Wait for the process to finish, outputting status messages every 5s.
  final stopwatch = Stopwatch()..start();
  final timer = Timer.periodic(
    const Duration(seconds: 5),
    (_) => io.stderr.write('Waiting ... ${stopwatch.elapsed.inSeconds}s\r'),
  );

  final outputFile = io.File(output).openWrite();

  // Pipe errors to stderr.
  final stderr = process.stderr.listen(io.stderr.add);

  final exitCode = await process.exitCode;

  // Pipe stdout to the output file.
  await process.stdout.pipe(outputFile);

  timer.cancel();
  await outputFile.close();
  await stderr.cancel();

  if (exitCode != 0) {
    io.stderr.writeln();
    io.stderr.writeln('Error $exitCode running "${command.join(' ')}"');
    io.exitCode = 1;
    return;
  }

  io.stderr.writeln(
    ''
    'Wrote "${command.join(' ')}" to "$output" in '
    '${stopwatch.elapsed.inSeconds}s',
  );
}

Future<int> _patch(io.File target, {required io.File patch}) async {
  final targetDoc = yaml.loadYamlDocument(
    target.readAsStringSync(),
    sourceUrl: target.uri,
  );
  final patchDoc = yaml.loadYamlDocument(
    patch.readAsStringSync(),
    sourceUrl: patch.uri,
  );

  final targetNode = targetDoc.contents;
  final patchNode = patchDoc.contents;

  // Merge the patch into the target.
  if (targetNode is! yaml.YamlMap) {
    throw StateError('Expected ${target.path} to be a YAML map');
  }
  if (patchNode is! yaml.YamlMap) {
    throw StateError('Expected ${patch.path} to be a YAML map');
  }

  final targetCopy = json.decode(json.encode(targetNode)) as Map;

  // Merge the patch into the target recursively.
  var patched = 0;
  void merge(Map target, Map patch) {
    for (final key in patch.keys) {
      final value = patch[key];
      if (value is Map) {
        if (!target.containsKey(key) || target[key] is! Map) {
          patched++;
          target[key] = value;
        } else {
          merge(target[key] as Map, value);
        }
      } else {
        target[key] = value;
      }
    }
  }

  merge(targetCopy, patchNode);
  target.writeAsStringSync(json.encode(targetCopy));
  return patched;
}

final _parser = ArgParser()
  ..addFlag(
    'help',
    abbr: 'h',
    help: 'Print this help message.',
    negatable: false,
  )
  ..addFlag(
    'dry-run',
    help: 'Prints the commands that would be executed, but do not run them.',
    negatable: false,
  )
  ..addOption(
    'dart-bin',
    abbr: 'b',
    help: ''
        'The path to a `dart` binary to run `dart analyze`.\n\n'
        'If not provided, the `dart` binary in the system PATH will be used.',
    defaultsTo: 'dart',
  )
  ..addOption(
    'format',
    help: 'Specifies the format to display errors.',
    allowed: ['machine', 'json'],
    defaultsTo: 'machine',
  )
  ..addOption(
    'output',
    abbr: 'o',
    help: ''
        'Specifies the file to write the output to.\n\n'
        'May use date/time formats supported by package:intl:\n'
        'https://pub.dev/packages/intl#date-formatting-and-parsing',
    defaultsTo: 'output/{DATE:yyyy_MM_dd}.{EXT}',
  )
  ..addOption(
    'patch',
    abbr: 'p',
    help: ''
        'Specifies a YAML file to merge with the default configuration.\n\n'
        'This is useful for setting defaults for the `dart analyze` command '
        'that will be run ephemerally, without modifying the project\'s '
        'actual configuration.\n\n'
        'Defaults to "analysis_options.dats.yaml" in the current directory.',
    defaultsTo: 'analysis_options.dats.yaml',
  )
  ..addSeparator(
    'Trailing options are passed directly to `dart analyze`.',
  );
