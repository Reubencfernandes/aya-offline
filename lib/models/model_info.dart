// Definitions for all available Aya model variants and quantizations.

class AyaModel {
  final String family;
  final String displayName;
  final String description;
  final String quant;
  final String fileName;
  final String downloadUrl;
  /// Approximate file size in MB.
  final int sizeMB;

  const AyaModel({
    required this.family,
    required this.displayName,
    required this.description,
    required this.quant,
    required this.fileName,
    required this.downloadUrl,
    required this.sizeMB,
  });
}

/// All downloadable Aya model variants.
/// Quantizations: q4_0 (smallest), q4_k_m (recommended), q8_0 (high quality).
/// bf16/f16 omitted — too large for mobile devices.
const ayaModels = [
  // Global — 70+ languages
  AyaModel(
    family: 'global',
    displayName: 'Aya Global',
    description: '70+ languages worldwide',
    quant: 'q4_k_m',
    fileName: 'tiny-aya-global-q4_k_m.gguf',
    downloadUrl: 'https://huggingface.co/CohereLabs/tiny-aya-global-GGUF/resolve/main/tiny-aya-global-q4_k_m.gguf',
    sizeMB: 1800,
  ),
  AyaModel(
    family: 'global',
    displayName: 'Aya Global',
    description: '70+ languages worldwide',
    quant: 'q4_0',
    fileName: 'tiny-aya-global-q4_0.gguf',
    downloadUrl: 'https://huggingface.co/CohereLabs/tiny-aya-global-GGUF/resolve/main/tiny-aya-global-q4_0.gguf',
    sizeMB: 1600,
  ),
  AyaModel(
    family: 'global',
    displayName: 'Aya Global',
    description: '70+ languages worldwide',
    quant: 'q8_0',
    fileName: 'tiny-aya-global-q8_0.gguf',
    downloadUrl: 'https://huggingface.co/CohereLabs/tiny-aya-global-GGUF/resolve/main/tiny-aya-global-q8_0.gguf',
    sizeMB: 3200,
  ),

  // Earth — European & related languages
  AyaModel(
    family: 'earth',
    displayName: 'Aya Earth',
    description: 'European & related languages',
    quant: 'q4_k_m',
    fileName: 'tiny-aya-earth-q4_k_m.gguf',
    downloadUrl: 'https://huggingface.co/CohereLabs/tiny-aya-earth-GGUF/resolve/main/tiny-aya-earth-q4_k_m.gguf',
    sizeMB: 1800,
  ),
  AyaModel(
    family: 'earth',
    displayName: 'Aya Earth',
    description: 'European & related languages',
    quant: 'q4_0',
    fileName: 'tiny-aya-earth-q4_0.gguf',
    downloadUrl: 'https://huggingface.co/CohereLabs/tiny-aya-earth-GGUF/resolve/main/tiny-aya-earth-q4_0.gguf',
    sizeMB: 1600,
  ),
  AyaModel(
    family: 'earth',
    displayName: 'Aya Earth',
    description: 'European & related languages',
    quant: 'q8_0',
    fileName: 'tiny-aya-earth-q8_0.gguf',
    downloadUrl: 'https://huggingface.co/CohereLabs/tiny-aya-earth-GGUF/resolve/main/tiny-aya-earth-q8_0.gguf',
    sizeMB: 3200,
  ),

  // Fire — South & Southeast Asian languages
  AyaModel(
    family: 'fire',
    displayName: 'Aya Fire',
    description: 'South & Southeast Asian languages',
    quant: 'q4_k_m',
    fileName: 'tiny-aya-fire-q4_k_m.gguf',
    downloadUrl: 'https://huggingface.co/CohereLabs/tiny-aya-fire-GGUF/resolve/main/tiny-aya-fire-q4_k_m.gguf',
    sizeMB: 1800,
  ),
  AyaModel(
    family: 'fire',
    displayName: 'Aya Fire',
    description: 'South & Southeast Asian languages',
    quant: 'q4_0',
    fileName: 'tiny-aya-fire-q4_0.gguf',
    downloadUrl: 'https://huggingface.co/CohereLabs/tiny-aya-fire-GGUF/resolve/main/tiny-aya-fire-q4_0.gguf',
    sizeMB: 1600,
  ),
  AyaModel(
    family: 'fire',
    displayName: 'Aya Fire',
    description: 'South & Southeast Asian languages',
    quant: 'q8_0',
    fileName: 'tiny-aya-fire-q8_0.gguf',
    downloadUrl: 'https://huggingface.co/CohereLabs/tiny-aya-fire-GGUF/resolve/main/tiny-aya-fire-q8_0.gguf',
    sizeMB: 3200,
  ),

  // Water — East Asian, African & Middle Eastern languages
  AyaModel(
    family: 'water',
    displayName: 'Aya Water',
    description: 'East Asian, African & Middle Eastern languages',
    quant: 'q4_k_m',
    fileName: 'tiny-aya-water-q4_k_m.gguf',
    downloadUrl: 'https://huggingface.co/CohereLabs/tiny-aya-water-GGUF/resolve/main/tiny-aya-water-q4_k_m.gguf',
    sizeMB: 1800,
  ),
  AyaModel(
    family: 'water',
    displayName: 'Aya Water',
    description: 'East Asian, African & Middle Eastern languages',
    quant: 'q4_0',
    fileName: 'tiny-aya-water-q4_0.gguf',
    downloadUrl: 'https://huggingface.co/CohereLabs/tiny-aya-water-GGUF/resolve/main/tiny-aya-water-q4_0.gguf',
    sizeMB: 1600,
  ),
  AyaModel(
    family: 'water',
    displayName: 'Aya Water',
    description: 'East Asian, African & Middle Eastern languages',
    quant: 'q8_0',
    fileName: 'tiny-aya-water-q8_0.gguf',
    downloadUrl: 'https://huggingface.co/CohereLabs/tiny-aya-water-GGUF/resolve/main/tiny-aya-water-q8_0.gguf',
    sizeMB: 3200,
  ),
];

/// Group models by family for the picker UI.
Map<String, List<AyaModel>> get modelsByFamily {
  final map = <String, List<AyaModel>>{};
  for (final m in ayaModels) {
    (map[m.family] ??= []).add(m);
  }
  return map;
}
