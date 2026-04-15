import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class SearchBarWidget extends StatefulWidget {
  const SearchBarWidget({
    super.key,
    this.controller,
    this.onSubmit,
    this.onTap,
    this.autofocus = false,
    this.hintText = 'Search videos, music...',
  });

  final TextEditingController? controller;
  final ValueChanged<String>? onSubmit;
  final VoidCallback? onTap;
  final bool autofocus;
  final String hintText;

  @override
  State<SearchBarWidget> createState() => _SearchBarWidgetState();
}

class _SearchBarWidgetState extends State<SearchBarWidget> {
  late TextEditingController _ctrl;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _ctrl = widget.controller ?? TextEditingController();
    _hasText = _ctrl.text.isNotEmpty;
    _ctrl.addListener(() {
      final has = _ctrl.text.isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    if (widget.controller == null) _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      autofocus: widget.autofocus,
      onTap: widget.onTap,
      onSubmitted: widget.onSubmit,
      textInputAction: TextInputAction.search,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
      decoration: InputDecoration(
        hintText: widget.hintText,
        prefixIcon: const Icon(Icons.search, color: AppColors.textHint, size: 20),
        suffixIcon: _hasText
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18, color: AppColors.textHint),
                onPressed: () {
                  _ctrl.clear();
                  widget.onSubmit?.call('');
                },
              )
            : null,
      ),
    );
  }
}
