import 'dart:io' as io;

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

void main(List<String> args) async {
  final results = _parser.parse(args);
  if (results.flag('help')) {
    io.stderr.writeln(_parser.usage);
    return;
  }

  final outputDir = io.Directory('output');

  var base = results.option('base');
  var against = results.option('against');
  if (base == null || against == null) {
    if (!outputDir.existsSync()) {
      io.stderr.writeln('No output directory found.');
      io.stderr.writeln(_parser.usage);
      io.exitCode = 1;
      return;
    }

    // Find all *.txt files in lexographical order.
    final txtFiles = outputDir.listSync().whereType<io.File>().where((file) {
      return p.extension(file.path) == '.txt';
    }).toList();
    txtFiles.sort((a, b) => a.path.compareTo(b.path));

    if (txtFiles.isEmpty) {
      io.stderr.writeln('No *.txt files found in output directory.');
      io.exitCode = 1;
      return;
    }

    base ??= txtFiles.first.path;

    if (against == null) {
      // Find the next file after the base file.
      final baseIndex = txtFiles.indexWhere((file) => file.path == base);
      if (baseIndex == -1) {
        io.stderr.writeln('Base file not found in output directory.');
        io.exitCode = 1;
        return;
      }

      if (baseIndex + 1 >= txtFiles.length) {
        io.stderr.writeln('No file to compare against.');
        io.exitCode = 1;
        return;
      }

      against = txtFiles[baseIndex + 1].path;
    }
  }

  io.stderr.writeln('Comparing $base against $against.');

  // Do a very dirty in-memory diff.
  final baseLines = io.File(base).readAsLinesSync();
  final againstLines = io.File(against).readAsLinesSync();

  // Group by file#symbol
  final baseGroups = <String, int>{};
  final againstGroups = <String, int>{};

  void fill(Map<String, int> map, List<String> lines) {
    for (final line in lines) {
      final parts = _AnalysisLog(line.split('|'));
      final key = parts.key;
      map[key] = (map[key] ?? 0) + 1;
    }
  }

  fill(baseGroups, baseLines);
  fill(againstGroups, againstLines);

  // Print summaries when they are different.
  for (final key in baseGroups.keys.toSet()..addAll(againstGroups.keys)) {
    final baseCount = baseGroups[key] ?? 0;
    final againstCount = againstGroups[key] ?? 0;
    if (baseCount != againstCount) {
      io.stdout.writeln(
        'Difference in $key:\n$baseCount in base, $againstCount in against.',
      );
    }
  }
}

extension type _AnalysisLog(List<String> _) {
  String get type => _[2];
  String get path => _[3];
  String get message => _[7];

  String get key {
    var result = '$type @${p.basename(path)}';
    if (type == 'DEPRECATED_MEMBER_USE') {
      var name = message.substring(1, message.indexOf("'", 1));
      result += ' $name';
    }
    return result;
  }
}

final _parser = ArgParser()
  ..addFlag(
    'help',
    abbr: 'h',
    help: 'Print this help message.',
    negatable: false,
  )
  ..addOption(
    'base',
    abbr: 'b',
    help: ''
        'The base file to compare against.\n\n'
        'Defaults to next file in the same directory in lexographical order.',
  )
  ..addOption(
    'against',
    abbr: 'a',
    help: ''
        'The file to compare against the base file.\n\n'
        'Defaults to first file in output/*.txt in lexographical order.',
  );
