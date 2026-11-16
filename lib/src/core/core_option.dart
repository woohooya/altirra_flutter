/// A libretro core option as declared by the Altirra core.
class CoreOption {
  const CoreOption({
    required this.key,
    required this.label,
    required this.info,
    required this.category,
    required this.defaultValue,
    required this.values,
    required this.visible,
  });

  final String key;
  final String label;
  final String info;
  final String category;
  final String defaultValue;
  final List<({String value, String label})> values;
  final bool visible;

  String labelFor(String? value) {
    for (final v in values) {
      if (v.value == value) return v.label;
    }
    return value ?? '';
  }

  /// Options that only take effect after a cold reset.
  bool get needsReset => const {
        'altirra_system',
        'altirra_memory',
        'altirra_video_standard',
        'altirra_basic',
        'altirra_os_firmware',
        'altirra_basic_firmware',
        'altirra_5200_bios',
        'altirra_cpu',
        'altirra_stereo_pokey',
        'altirra_vbxe',
        'altirra_covox',
        'altirra_soundboard',
        'altirra_rapidus',
        'altirra_sio_patch',
        'altirra_cart_mapper',
      }.contains(key);
}
