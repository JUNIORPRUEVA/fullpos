Map<String, String> buildElectronicCompanyLocators({
  required int? sessionCompanyId,
  String? companyCloudId,
  String? companyRnc,
}) {
  final trimmedCloudId = companyCloudId?.trim() ?? '';
  final trimmedRnc = companyRnc?.trim() ?? '';
  final hasCloudIdentity =
      trimmedCloudId.isNotEmpty || trimmedRnc.isNotEmpty;

  final locators = <String, String>{};
  if (trimmedCloudId.isNotEmpty) {
    locators['companyCloudId'] = trimmedCloudId;
  }
  if (trimmedRnc.isNotEmpty) {
    locators['companyRnc'] = trimmedRnc;
  }
  if (!hasCloudIdentity && sessionCompanyId != null) {
    locators['companyId'] = sessionCompanyId.toString();
  }
  return locators;
}