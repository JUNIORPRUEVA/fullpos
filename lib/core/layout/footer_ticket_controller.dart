import 'package:flutter_riverpod/flutter_riverpod.dart';

class FooterTicketTabData {
  const FooterTicketTabData({
    required this.label,
    required this.isActive,
    this.showAlertDot = false,
    this.canDelete = false,
  });

  final String label;
  final bool isActive;
  final bool showAlertDot;
  final bool canDelete;
}

class FooterTicketController {
  void Function()? _onAdd;
  void Function(int index)? _onSelect;
  Future<void> Function(int index)? _onRename;
  void Function(int index)? _onDelete;

  List<FooterTicketTabData> tabs = const <FooterTicketTabData>[];

  void bind({
    void Function()? onAdd,
    void Function(int index)? onSelect,
    Future<void> Function(int index)? onRename,
    void Function(int index)? onDelete,
  }) {
    _onAdd = onAdd;
    _onSelect = onSelect;
    _onRename = onRename;
    _onDelete = onDelete;
  }

  void updateTabs(List<FooterTicketTabData> nextTabs) {
    tabs = List<FooterTicketTabData>.unmodifiable(nextTabs);
  }

  void clear() {
    tabs = const <FooterTicketTabData>[];
  }

  void add() => _onAdd?.call();

  void select(int index) => _onSelect?.call(index);

  Future<void>? rename(int index, [String? name]) => _onRename?.call(index);

  void delete(int index) => _onDelete?.call(index);
}

final footerTicketControllerProvider = Provider<FooterTicketController>((ref) {
  return FooterTicketController();
});
