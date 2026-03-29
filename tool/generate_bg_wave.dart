import 'dart:io';

Future<void> main() async {
  const sourcePath = 'assets/backgrounds/bg_wave_source.svg';
  const outputPath = 'assets/backgrounds/bg_wave.webp';

  final source = File(sourcePath);
  if (!source.existsSync()) {
    throw StateError('No se encontro $sourcePath.');
  }

  final outputDir = Directory('assets/backgrounds');
  if (!outputDir.existsSync()) {
    outputDir.createSync(recursive: true);
  }

  final npxCommand = Platform.isWindows ? 'npx.cmd' : 'npx';

  final result = await Process.run(npxCommand, <String>[
    '--yes',
    'sharp-cli',
    '-i',
    sourcePath,
    '-o',
    outputPath,
    '--density',
    '144',
    '--format',
    'webp',
    '--quality',
    '58',
    '--alphaQuality',
    '70',
    '--effort',
    '5',
  ]);

  if (result.exitCode != 0) {
    stderr.write(result.stderr);
    throw ProcessException(
      npxCommand,
      const <String>['sharp-cli'],
      result.stderr.toString(),
      result.exitCode,
    );
  }

  final output = File(outputPath);
  if (!output.existsSync()) {
    throw StateError('No se genero $outputPath.');
  }

  stdout.writeln('Generado $outputPath (${output.lengthSync()} bytes)');
}
