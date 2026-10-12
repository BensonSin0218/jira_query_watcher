import 'package:flutter/material.dart';

import '../models.dart';

class WatchEditorDialog extends StatefulWidget {
  const WatchEditorDialog({super.key, this.watch});

  final JqlWatch? watch;

  @override
  State<WatchEditorDialog> createState() => _WatchEditorDialogState();
}

class _WatchEditorDialogState extends State<WatchEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _jqlController;
  late double _intervalMinutes;
  late bool _enabled;
  late final List<NotificationPeriod> _notificationPeriods;
  String? _notificationError;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.watch?.name ?? '');
    _jqlController = TextEditingController(text: widget.watch?.jql ?? '');
    _intervalMinutes = (widget.watch?.intervalMinutes ?? 5).toDouble();
    _enabled = widget.watch?.enabled ?? true;
    _notificationPeriods = List.of(
      (widget.watch ?? const JqlWatch()).notificationPeriods,
    );
  }

  void _submit() {
    final fieldsValid = _formKey.currentState!.validate();
    final watch = (widget.watch ?? const JqlWatch()).copyWith(
      name: _nameController.text.trim(),
      jql: _jqlController.text.trim(),
      intervalMinutes: _intervalMinutes.round(),
      enabled: _enabled,
      notificationPeriods: List.unmodifiable(_notificationPeriods),
    );
    setState(() => _notificationError = watch.notificationScheduleError);
    if (!fieldsValid || _notificationError != null) return;
    Navigator.of(context).pop(watch);
  }

  Future<void> _editNotificationPeriod([int? index]) async {
    final period = await showDialog<NotificationPeriod>(
      context: context,
      builder: (_) => _NotificationPeriodDialog(
        period: index == null ? null : _notificationPeriods[index],
        otherPeriods: [
          for (var i = 0; i < _notificationPeriods.length; i++)
            if (i != index) _notificationPeriods[i],
        ],
      ),
    );
    if (!mounted || period == null) return;
    setState(() {
      if (index == null) {
        _notificationPeriods.add(period);
      } else {
        _notificationPeriods[index] = period;
      }
      _notificationError = null;
    });
  }

  Widget _buildNotificationPeriods() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.schedule, size: 20),
            const SizedBox(width: 8),
            const Text('通知時間', style: TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _editNotificationPeriod(),
              icon: const Icon(Icons.add),
              label: const Text('新增時段'),
            ),
          ],
        ),
        const Text('依電腦本地時間運作；時段外暫停檢查，進入時段後自動恢復。'),
        for (var i = 0; i < _notificationPeriods.length; i++)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '時段 ${i + 1} · ${_notificationPeriods[i].timeLabel}',
                      ),
                      Text(_notificationPeriods[i].weekdayLabel),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _editNotificationPeriod(i),
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: '編輯時段 ${i + 1}',
                ),
                IconButton(
                  onPressed: () => setState(() {
                    _notificationPeriods.removeAt(i);
                    _notificationError = null;
                  }),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '刪除時段 ${i + 1}',
                ),
              ],
            ),
          ),
        if (_notificationPeriods.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text('尚未設定通知時段，請新增至少一個時段。'),
          ),
        if (_notificationError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _notificationError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.watch != null;
    return AlertDialog(
      title: Text(isEditing ? '編輯 JQL 監聽' : '新增 JQL 監聽'),
      content: SizedBox(
        width: 540,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: '名稱（選填）',
                    hintText: '例如：待處理缺陷',
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _jqlController,
                  minLines: 4,
                  maxLines: 8,
                  autofocus: !isEditing,
                  decoration: const InputDecoration(
                    labelText: 'JQL',
                    hintText:
                        'project = ABC AND status != Done ORDER BY updated DESC',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '請輸入 JQL。';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Text(
                      '檢查間隔',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 12),
                    Text('${_intervalMinutes.round()} 分鐘'),
                    Expanded(
                      child: Slider(
                        value: _intervalMinutes,
                        min: 1,
                        max: 30,
                        divisions: 29,
                        label: '${_intervalMinutes.round()} 分鐘',
                        onChanged: (value) {
                          setState(() => _intervalMinutes = value);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildNotificationPeriods(),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('啟用此監聽'),
                  value: _enabled,
                  onChanged: (value) => setState(() => _enabled = value),
                ),
                Text(
                  '可設定範圍：1–30 分鐘。第一次成功查詢只建立基準，不會立即發送變化通知。',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('儲存')),
      ],
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _jqlController.dispose();
    super.dispose();
  }
}

class _NotificationPeriodDialog extends StatefulWidget {
  const _NotificationPeriodDialog({this.period, required this.otherPeriods});

  final NotificationPeriod? period;
  final List<NotificationPeriod> otherPeriods;

  @override
  State<_NotificationPeriodDialog> createState() =>
      _NotificationPeriodDialogState();
}

class _NotificationPeriodDialogState extends State<_NotificationPeriodDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _startController;
  late final TextEditingController _endController;
  late final Set<int> _weekdays;
  String? _error;

  @override
  void initState() {
    super.initState();
    final period = widget.period ?? const NotificationPeriod();
    _startController = TextEditingController(
      text: NotificationPeriod.formatMinute(period.startMinute),
    );
    _endController = TextEditingController(
      text: NotificationPeriod.formatMinute(period.endMinute),
    );
    _weekdays = period.weekdays.toSet();
  }

  int? _parseTime(String value) {
    final match = RegExp(
      r'^([01]\d|2[0-3]):([0-5]\d)$',
    ).firstMatch(value.trim());
    if (match == null) return null;
    return int.parse(match[1]!) * 60 + int.parse(match[2]!);
  }

  Future<void> _pickTime(TextEditingController controller, String label) async {
    final minute = _parseTime(controller.text) ?? 0;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
      helpText: label,
      cancelText: '取消',
      confirmText: '確定',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (!mounted || time == null) return;
    setState(() {
      controller.text = NotificationPeriod.formatMinute(
        time.hour * 60 + time.minute,
      );
      _error = null;
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final period = NotificationPeriod(
      startMinute: _parseTime(_startController.text)!,
      endMinute: _parseTime(_endController.text)!,
      weekdays: List.unmodifiable(_weekdays.toList()..sort()),
    );
    final error =
        period.validationError ??
        (widget.otherPeriods.any(period.overlaps)
            ? '此時段與其他時段重疊，請調整時間或星期。'
            : null);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(period);
  }

  Widget _buildTimeField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.datetime,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'HH:mm',
        errorMaxLines: 2,
        suffixIcon: IconButton(
          onPressed: () => _pickTime(controller, label),
          icon: const Icon(Icons.schedule),
          tooltip: '選擇$label',
        ),
      ),
      validator: (value) =>
          _parseTime(value ?? '') == null ? '請輸入 00:00–23:59（HH:mm）。' : null,
      onChanged: (_) => setState(() => _error = null),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.period == null ? '新增通知時段' : '編輯通知時段'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildTimeField(_startController, '開始時間')),
                    const SizedBox(width: 16),
                    Expanded(child: _buildTimeField(_endController, '結束時間')),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('24 小時制，包含開始及結束分鐘；跨午夜請分成兩個時段。'),
                const SizedBox(height: 18),
                const Text('星期', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var day = 1; day <= 7; day++)
                      FilterChip(
                        label: Text(
                          '星期${NotificationPeriod.weekdayNames[day - 1]}',
                        ),
                        selected: _weekdays.contains(day),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            _weekdays.add(day);
                          } else {
                            _weekdays.remove(day);
                          }
                          _error = null;
                        }),
                      ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('確定')),
      ],
    );
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }
}
