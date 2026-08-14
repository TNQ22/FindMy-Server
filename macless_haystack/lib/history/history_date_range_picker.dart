import 'package:flutter/material.dart';

/// A compact date-range picker bar that replaces the old DaysSelectionSlider.
///
/// Offers quick preset buttons (Today / 7 days / 30 days) and a custom
/// date-range picker. Passes the selected range to [onRangeChanged].
class HistoryDateRangePicker extends StatefulWidget {
  final void Function(DateTime from, DateTime to) onRangeChanged;
  final bool isLoading;

  const HistoryDateRangePicker({
    super.key,
    required this.onRangeChanged,
    this.isLoading = false,
  });

  @override
  State<HistoryDateRangePicker> createState() => _HistoryDateRangePickerState();
}

class _HistoryDateRangePickerState extends State<HistoryDateRangePicker> {
  // 0 = Today, 1 = 7 days, 2 = 30 days, 3 = All time, 4 = Custom
  int _selectedPreset = 0;

  // Custom range (only when _selectedPreset == 4)
  DateTimeRange? _customRange;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history_rounded, size: 18),
              const SizedBox(width: 6),
              Text(
                _rangeLabel(),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const Spacer(),
              if (widget.isLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _presetChip('Hôm nay', 0),
                const SizedBox(width: 6),
                _presetChip('2 ngày', 5),
                const SizedBox(width: 6),
                _presetChip('7 ngày', 1),
                const SizedBox(width: 6),
                _presetChip('30 ngày', 2),
                const SizedBox(width: 6),
                _presetChip('Tất cả', 3),
                const SizedBox(width: 6),
                _customChip(),
              ],
            ),
          ),
          // Show selected custom range label
          if (_selectedPreset == 4 && _customRange != null)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                '${_fmtDate(_customRange!.start)}  →  ${_fmtDate(_customRange!.end)}',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w500),
              ),
            ),
        ],
      ),
    );
  }

  Widget _presetChip(String label, int preset) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      selected: _selectedPreset == preset,
      onSelected: (_) {
        setState(() => _selectedPreset = preset);
        _emitPreset(preset);
      },
      selectedColor: Theme.of(context).colorScheme.primaryContainer,
      elevation: 1,
    );
  }

  Widget _customChip() {
    return ActionChip(
      avatar: Icon(
        Icons.date_range_rounded,
        size: 16,
        color: _selectedPreset == 4
            ? Theme.of(context).colorScheme.primary
            : null,
      ),
      label: Text(
        'Tùy chọn...',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: _selectedPreset == 4
              ? Theme.of(context).colorScheme.primary
              : null,
        ),
      ),
      onPressed: _pickCustomRange,
      elevation: 1,
    );
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final initial = _customRange ??
        DateTimeRange(
          start: now.subtract(const Duration(days: 7)),
          end: now,
        );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: initial,
      helpText: 'Chọn khoảng thời gian',
      saveText: 'Áp dụng',
    );

    if (picked != null) {
      setState(() {
        _selectedPreset = 4;
        _customRange = picked;
      });
      widget.onRangeChanged(
        picked.start,
        picked.end.add(const Duration(hours: 23, minutes: 59, seconds: 59)),
      );
    }
  }

  void _emitPreset(int preset) {
    final now = DateTime.now();
    switch (preset) {
      case 0: // Today
        widget.onRangeChanged(
            DateTime(now.year, now.month, now.day), now);
        break;
      case 5: // 2 days
        widget.onRangeChanged(now.subtract(const Duration(days: 2)), now);
        break;
      case 1: // 7 days
        widget.onRangeChanged(now.subtract(const Duration(days: 7)), now);
        break;
      case 2: // 30 days
        widget.onRangeChanged(now.subtract(const Duration(days: 30)), now);
        break;
      case 3: // All time — from_ts = 0 means no lower bound
        widget.onRangeChanged(DateTime.fromMillisecondsSinceEpoch(0), now);
        break;
    }
  }

  String _rangeLabel() {
    switch (_selectedPreset) {
      case 0:
        return 'Hôm nay';
      case 5:
        return '2 ngày gần nhất';
      case 1:
        return '7 ngày gần nhất';
      case 2:
        return '30 ngày gần nhất';
      case 3:
        return 'Tất cả dữ liệu';
      case 4:
        if (_customRange != null) {
          return '${_fmtDate(_customRange!.start)} – ${_fmtDate(_customRange!.end)}';
        }
        return 'Khoảng tùy chọn';
      default:
        return 'Lịch sử';
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
