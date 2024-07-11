# `D.A.T.S`: Dart Analyzer Time Series

This package is a demo of using `dart analyze` to produce a time-series of
analysis results for a Dart project.

## Usage

### Running analyze

`dats` is a single command-line tool that runs `dart analyze` on a project and
outputs a time-series of analysis results.

```shell
dart global pub activate dats --source git https://github.com/matanlurey/dats

# If the system cache is in PATH (https://dart.dev/tools/pub/glossary#system-cache):
dats .

# Otherwise:
dart pub global run dats .
```

The default is a machine-parseable file in `output/{DATE:yyyy_MM_dd}.txt`.

### Patching `analysis_options.yaml`

It is possible to apply a limited _patch_ to the `analysis_options.yaml` file
in the current working directory before running `dart analyze`, which could be
useful, for example, to temporarily enable a lint or warning. First, write a
patch file, which is a YAML file with the same structure as the
`analysis_options.yaml` file, but with only the keys you want to change:

```yaml
# analysis_options.dats.yaml

analyzer:
  errors:
    # Is ignored in the main `analysis_options.yaml` file.
    deprecated_member_use: info
```

By default, `dats` looks for a file named `analysis_options.dats.yaml` in the
current working directory. To use a different file, pass the `--patch` flag:

```shell
dats --patch=analysis_options.dats.yaml .
```

### Diffing analysis

To understand how analysis changed over time, use `dats_diff`:

```shell
dats_diff .
```

By default, it picks the last two edited files in `output/` and compares them.

> [!IMPORTANT]
> Only `.txt` files are currently supported in this demo.
