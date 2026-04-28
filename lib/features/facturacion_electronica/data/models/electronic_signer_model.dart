class ElectronicSignerModel {
  const ElectronicSignerModel({
    required this.signerFullName,
    required this.signerDocumentType,
    required this.signerDocumentNumber,
    required this.signerAuthorizedForDgii,
  });

  final String signerFullName;
  final String signerDocumentType;
  final String signerDocumentNumber;
  final bool signerAuthorizedForDgii;

  factory ElectronicSignerModel.empty() {
    return const ElectronicSignerModel(
      signerFullName: '',
      signerDocumentType: 'CEDULA',
      signerDocumentNumber: '',
      signerAuthorizedForDgii: false,
    );
  }

  factory ElectronicSignerModel.fromMap(Map<String, dynamic> map) {
    return ElectronicSignerModel(
      signerFullName: map['signerFullName']?.toString().trim() ?? '',
      signerDocumentType:
          map['signerDocumentType']
                  ?.toString()
                  .trim()
                  .toUpperCase()
                  .isNotEmpty ==
              true
          ? map['signerDocumentType'].toString().trim().toUpperCase()
          : 'CEDULA',
      signerDocumentNumber:
          map['signerDocumentNumber']?.toString().trim().replaceAll(
            RegExp(r'[-\s]'),
            '',
          ) ??
          '',
      signerAuthorizedForDgii: map['signerAuthorizedForDgii'] == true,
    );
  }

  ElectronicSignerModel copyWith({
    String? signerFullName,
    String? signerDocumentType,
    String? signerDocumentNumber,
    bool? signerAuthorizedForDgii,
  }) {
    return ElectronicSignerModel(
      signerFullName: signerFullName ?? this.signerFullName,
      signerDocumentType: signerDocumentType ?? this.signerDocumentType,
      signerDocumentNumber: signerDocumentNumber ?? this.signerDocumentNumber,
      signerAuthorizedForDgii:
          signerAuthorizedForDgii ?? this.signerAuthorizedForDgii,
    );
  }
}

class ElectronicSignerCertificateComparison {
  const ElectronicSignerCertificateComparison({
    required this.certificateSubject,
    required this.certificateSignerName,
    required this.certificateDocumentNumber,
    required this.signerNameMatchesCertificate,
    required this.signerDocumentMatchesCertificate,
    required this.certificateLooksNaturalPerson,
    required this.delegationLikelyRequired,
    required this.warningCodes,
  });

  final String? certificateSubject;
  final String? certificateSignerName;
  final String? certificateDocumentNumber;
  final bool signerNameMatchesCertificate;
  final bool signerDocumentMatchesCertificate;
  final bool certificateLooksNaturalPerson;
  final bool delegationLikelyRequired;
  final List<String> warningCodes;

  factory ElectronicSignerCertificateComparison.fromMap(
    Map<String, dynamic> map,
  ) {
    return ElectronicSignerCertificateComparison(
      certificateSubject:
          map['certificateSubject']?.toString() ??
          map['certificateSubjectShort']?.toString(),
      certificateSignerName:
          map['certificateSignerName']?.toString() ??
          map['certificateSubjectName']?.toString(),
      certificateDocumentNumber: map['certificateDocumentNumber']
          ?.toString()
          .trim()
          .replaceAll(RegExp(r'[-\s]'), ''),
      signerNameMatchesCertificate: map['signerNameMatchesCertificate'] == true,
      signerDocumentMatchesCertificate:
          map['signerDocumentMatchesCertificate'] == true,
      certificateLooksNaturalPerson:
          map['certificateLooksNaturalPerson'] == true ||
          map['certificateAppearsNaturalPerson'] == true,
      delegationLikelyRequired:
          map['delegationLikelyRequired'] == true ||
          map['requiresDgiiDelegationCheck'] == true,
      warningCodes:
          (map['warningCodes'] as List? ?? map['warnings'] as List?)
              ?.map((item) => item.toString())
              .toList(growable: false) ??
          const <String>[],
    );
  }
}
