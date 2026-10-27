import 'package:flutter/material.dart';
import '../../../core/haptics.dart';
import '../../../ui/theme.dart';

/// Inline expand-and-collapse panel to rename a Temple Light.
/// Features live preview, character counter, whitespace trimming, and validation.
/// Adapted from Boturo's `InlineRenamePanel` for Temple Lights.
class InlineDeviceRenamePanel extends StatefulWidget {
  const InlineDeviceRenamePanel({
    super.key,
    required this.initialName,
    required this.isExpanded,
    required this.onSave,
    required this.onCancel,
    required this.onToggleExpand,
  });

  final String initialName;
  final bool isExpanded;
  final Future<void> Function(String newName) onSave;
  final VoidCallback onCancel;
  final VoidCallback onToggleExpand;

  @override
  State<InlineDeviceRenamePanel> createState() => _InlineDeviceRenamePanelState();
}

class _InlineDeviceRenamePanelState extends State<InlineDeviceRenamePanel> {
  late final TextEditingController _controller;
  String? _errorText;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void didUpdateWidget(covariant InlineDeviceRenamePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialName != oldWidget.initialName && !_controller.text.isNotEmpty) {
      _controller.text = widget.initialName;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _validateAndSave() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _errorText = 'Name cannot be empty');
      return;
    }
    if (text.length > 32) {
      setState(() => _errorText = 'Maximum 32 characters allowed');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    try {
      AppHaptics.selection();
      await widget.onSave(text);
    } catch (e) {
      if (mounted) {
        setState(() => _errorText = 'Failed to rename: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: widget.isExpanded
          ? Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.amber.withValues(alpha: 0.4), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.amber.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title + Live Preview Chip
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.edit_note_rounded, size: 18, color: AppTheme.amber),
                          const SizedBox(width: 6),
                          Text('RENAME LIGHT', style: AppTheme.heading(size: 11, color: AppTheme.textMuted, letterSpacing: 1.1)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.amber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _controller.text.trim().isEmpty ? widget.initialName : _controller.text.trim(),
                          style: AppTheme.heading(size: 10, color: AppTheme.amber),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Text Field
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    maxLength: 32,
                    style: AppTheme.heading(size: 14),
                    onChanged: (val) {
                      if (_errorText != null) {
                        setState(() => _errorText = null);
                      } else {
                        setState(() {});
                      }
                    },
                    decoration: InputDecoration(
                      hintText: 'e.g. Mandir Sanctum, Puja Altar',
                      hintStyle: AppTheme.body(size: 13, color: AppTheme.textMuted),
                      errorText: _errorText,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppTheme.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppTheme.amber, width: 1.6),
                      ),
                      suffixIcon: _controller.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 16),
                              onPressed: () {
                                _controller.clear();
                                setState(() {});
                              },
                            )
                          : null,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Action Buttons (Cancel / Save)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _isSaving ? null : widget.onCancel,
                        child: Text('Cancel', style: AppTheme.heading(size: 12, color: AppTheme.textMuted)),
                      ),
                      const SizedBox(width: 6),
                      ElevatedButton(
                        onPressed: _isSaving ? null : _validateAndSave,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.amber,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text('Save Name', style: AppTheme.heading(size: 12, color: Colors.white)),
                      ),
                    ],
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
