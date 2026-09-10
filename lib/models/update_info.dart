class UpdateInfo {
  final String version;
  final bool mandatory;
  final String notes;
  final String url;

  const UpdateInfo({
    required this.version,
    required this.mandatory,
    required this.notes,
    required this.url,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) => UpdateInfo(
        version: json['version'] as String,
        mandatory: json['mandatory'] as bool,
        notes: json['notes'] as String,
        url: json['url'] as String,
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'mandatory': mandatory,
        'notes': notes,
        'url': url,
      };
}
