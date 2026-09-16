/// `dart run selenium:fetch_engine` — the one command a Dart dev runs after
/// `dart pub get` to pull the prebuilt pure-Aether engine (libselenium_core)
/// for their platform from GitHub releases. No Aether toolchain, no compiler.
///
/// Flags:
///   --tag <vX.Y.Z>   pin a specific engine release (default: EngineFetcher.engineVersion)
///   --force          re-download even if a cached copy is present
///   --path           just print where the engine is (or would be) cached, no download
///   -h, --help       show this help
library;

import 'dart:io';

import 'package:selenium/src/engine_fetcher.dart';

Future<void> main(List<String> args) async {
  var tag = EngineFetcher.engineVersion;
  var force = false;
  var pathOnly = false;

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    switch (a) {
      case '--tag':
        if (i + 1 >= args.length) {
          stderr.writeln('selenium: --tag needs a value (e.g. --tag v0.8.0)');
          exit(2);
        }
        tag = args[++i];
        break;
      case '--force':
        force = true;
        break;
      case '--path':
        pathOnly = true;
        break;
      case '-h':
      case '--help':
        stdout.writeln(
          'Usage: dart run selenium:fetch_engine [--tag vX.Y.Z] [--force] [--path]\n'
          '  Downloads + caches the prebuilt engine (libselenium_core) for this\n'
          '  platform from GitHub releases. --path prints the cache location only.',
        );
        return;
      default:
        if (a.startsWith('--tag=')) {
          tag = a.substring('--tag='.length);
        } else {
          stderr.writeln('selenium: unknown argument: $a');
          exit(2);
        }
    }
  }

  if (pathOnly) {
    stdout.writeln(EngineFetcher.cachedPath(tag));
    return;
  }

  stderr.writeln(
      'selenium: fetching engine ${EngineFetcher.assetName(tag)} ($tag) …');
  try {
    final path = await EngineFetcher.fetch(tag: tag, force: force);
    stderr.writeln('selenium: engine ready at $path');
    stderr.writeln(
        "selenium: `import 'package:selenium/selenium.dart'` will now load it "
        'automatically.');
  } on FetchException catch (e) {
    stderr.writeln('selenium: engine fetch failed: ${e.message}');
    exit(1);
  }
}
