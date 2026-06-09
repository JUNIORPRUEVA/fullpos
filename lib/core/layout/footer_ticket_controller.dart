import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FooterTicketTabData {
  const FooterTicketTabData({
    required this.label,
    required this.isActive,
    this.showAlertDot = false,
    this.canDelete = true,
  });

  final String label;
  final bool isActive;
  final bool showAlertDot;
  final bool canDelete;
}

class FooterTicketState {
  const FooterTicketState({
    this.enabled = false,
    this.tabs = const <FooterTicketTabData>[],
  });

  final bool enabled;
  final List<FooterTicketTabData> tabs;

  FooterTicketState copyWith({bool? enabled, List<FooterTicketTabData>? tabs}) {
    return FooterTicketState(
      enabled: enabled ?? this.enabled,
      tabs: tabs ?? this.tabs,
    );
  }
}

class FooterTicketController extends ChangeNotifier {
  FooterTicketState _state = const FooterTicketState();

  FooterTicketState get state => _state;

  Future<void> Function()? _onAdd;
  Future<void> Function(int index)? _onSelect;
  Future<void> Function(int index)? _onRename;
  Future<void> Function(int index)? _onDelete;

  void bind({
    required Future<void> Function() onAdd,
    required Future<void> Function(int index) onSelect,
    required Future<void> Function(int index) onRename,
    required Future<void> Function(int index) onDelete,
  }) {
    _onAdd = onAdd;
    _onSelect = onSelect;
    _onRename = onRename;
    _onDelete = onDelete;
  }

  void updateTabs(List<FooterTicketTabData> tabs) {
    _state = FooterTicketState(enabled: true, tabs: tabs);
    notifyListeners();
  }

  void clear() {
    _onAdd = null;
    _onSelect = null;
    _onRename = null;
    _onDelete = null;
    _state = const FooterTicketState();
    notifyListeners();
  }

  Future<void> add() async => _onAdd?.call();

  Future<void> select(int index) async => _onSelect?.call(index);

  Future<void> rename(int index) async => _onRename?.call(index);

  Future<void> delete(int index) async => _onDelete?.call(index);
}

final footerTicketControllerProvider =
    ChangeNotifierProvider<FooterTicketController>(
      (ref) => FooterTicketController(),
    );
