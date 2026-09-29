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
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.watch?.name ?? '');
    _jqlController = TextEditingController(text: widget.watch?.jql ?? '');
    _intervalMinutes = (widget.watch?.intervalMinutes ?? 5).toDouble();
    _enabled = widget.watch?.enabled ?? true;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final watch = widget.watch?.copyWith(
      name: _nameController.text.trim(),
      jql: _jqlController.text.trim(),
      intervalMinutes: _intervalMinutes.round(),
      enabled: _enabled,
    );
    Navigator.of(context).pop(
      watch ??
          JqlWatch(
            name: _nameController.text.trim(),
            jql: _jqlController.text.trim(),
            intervalMinutes: _intervalMinutes.round(),
            enabled: _enabled,
          ),
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
