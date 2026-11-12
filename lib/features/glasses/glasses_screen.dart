import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/color_show.dart';
import '../../models/compass.dart';
import '../../protocol/active_look_palette.dart';
import '../compass/compass_ribbon.dart';
import 'glasses_controller.dart';
import 'glasses_preview.dart';

/// Controls the connected glasses: shows status, previews the framebuffer and
/// sends the demo text.
class GlassesScreen extends StatefulWidget {
  const GlassesScreen({super.key, required this.controller});

  final GlassesController controller;

  @override
  State<GlassesScreen> createState() => _GlassesScreenState();
}

class _GlassesScreenState extends State<GlassesScreen> {
  final TextEditingController _textController = TextEditingController(
    text: 'Hello!',
  );

  /// Briefly highlights the preview when tapped, before opening full screen.
  Timer? _previewFlashTimer;
  bool _previewHighlighted = false;

  @override
  void initState() {
    super.initState();
    // The whole point of the demo: say hello as soon as we are connected.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.controller.connected) {
        widget.controller.showText(_textController.text);
      }
    });
  }

  @override
  void dispose() {
    _previewFlashTimer?.cancel();
    _textController.dispose();
    widget.controller.dispose();
    super.dispose();
  }

  Future<void> _disconnect() async {
    await widget.controller.disconnect();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    await widget.controller.showText(_textController.text);
  }

  /// Flashes the preview border, then opens the full-screen preview.
  void _openFullscreenPreview() {
    if (_previewFlashTimer != null) return;
    setState(() => _previewHighlighted = true);
    _previewFlashTimer = Timer(const Duration(milliseconds: 170), () {
      _previewFlashTimer = null;
      if (!mounted) return;
      setState(() => _previewHighlighted = false);
      _showFullscreenPreview();
    });
  }

  /// Shows the 304×256 preview edge to edge, for checking colors at a distance.
  void _showFullscreenPreview() {
    final controller = widget.controller;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: const Text('Экран очков'),
            ),
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: GlassesPreview(
                    text: controller.lastRenderedText,
                    textColor: controller.displayColor,
                    shapes: controller.frameShapes,
                    showUsableArea: false,
                    compassHeading: controller.compassDisplayHeading,
                    compassColor: controller.isColorCapable
                        ? ActiveLookColor.green
                        : ActiveLookColor.bright,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final theme = Theme.of(context);

        return Scaffold(
          appBar: AppBar(
            title: Text(controller.displayName),
            actions: [
              IconButton(
                tooltip: 'Обновить заряд',
                onPressed: controller.connected
                    ? controller.refreshBattery
                    : null,
                icon: const Icon(Icons.battery_std_outlined),
              ),
              IconButton(
                tooltip: 'Отключить',
                onPressed: _disconnect,
                icon: const Icon(Icons.link_off),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _StatusCard(controller: controller),
              if (controller.error != null) ...[
                const SizedBox(height: 12),
                _ErrorBanner(message: controller.error!),
              ],
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Что показывают очки',
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Во весь экран',
                            onPressed: _openFullscreenPreview,
                            icon: const Icon(Icons.fullscreen),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Имитация экрана 304×256 — чёрный цвет на реальной панели прозрачный',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _openFullscreenPreview,
                        child: GlassesPreview(
                          text: controller.lastRenderedText,
                          textColor: controller.displayColor,
                          shapes: controller.frameShapes,
                          highlight: _previewHighlighted,
                          compassHeading: controller.compassDisplayHeading,
                          compassColor: controller.isColorCapable
                              ? ActiveLookColor.green
                              : ActiveLookColor.bright,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // The compass only exists on mobile builds; desktop gets no
              // section at all rather than a disabled placeholder.
              if (controller.compassSupported) ...[
                const SizedBox(height: 16),
                _CompassCard(controller: controller),
              ],
              const SizedBox(height: 16),
              _ColorShowCard(controller: controller),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Показать текст',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _textController,
                        enabled: controller.connected,
                        maxLength: 60,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(
                          labelText: 'Текст на экране',
                          border: OutlineInputBorder(),
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Встроенный шрифт очков поддерживает только латиницу, '
                        'поэтому кириллица отправляется транслитом.',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (controller.isColorCapable) ...[
                        const SizedBox(height: 12),
                        _ColorPicker(
                          selected: controller.textColor,
                          onSelected: controller.setTextColor,
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed:
                                  controller.connected && !controller.busy
                                  ? _send
                                  : null,
                              icon: controller.busy
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.visibility),
                              label: const Text('Вывести на очки'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton(
                            onPressed: controller.connected && !controller.busy
                                ? controller.clearDisplay
                                : null,
                            child: const Text('Очистить'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Отправляется как hold → clear → ${controller.isColorCapable ? 'txtColor' : 'txt'} '
                        '→ flush: панель обновляется один раз, без мерцания.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Настройки экрана',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      _LumaSlider(
                        value: controller.luma,
                        enabled: controller.connected,
                        onChanged: controller.setLuma,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: controller.connected
                                ? () => controller.showDemoPattern(1)
                                : null,
                            icon: const Icon(Icons.grid_on),
                            label: const Text('Демо-шаблон'),
                          ),
                          OutlinedButton.icon(
                            onPressed: controller.connected
                                ? () => controller.showDemoPattern(0)
                                : null,
                            icon: const Icon(Icons.crop_square),
                            label: const Text('Залить экран'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  leading: const Icon(Icons.terminal),
                  title: const Text('Журнал протокола'),
                  subtitle: Text('${controller.log.length} строк'),
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: controller.log.length,
                        itemBuilder: (context, index) {
                          final line = controller.log[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              line,
                              style: const TextStyle(
                                fontFamily: 'Menlo',
                                fontSize: 11,
                                color: Color(0xFFBDBDBD),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.controller});

  final GlassesController controller;

  @override
  Widget build(BuildContext context) {
    final info = controller.info;
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  controller.connected
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_disabled,
                  color: controller.connected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Text(
                  controller.connected ? 'Подключено' : 'Нет подключения',
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                if (info.batteryLevel != null)
                  _Pill(
                    icon: Icons.battery_5_bar,
                    label: '${info.batteryLevel}%',
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _InfoRow(label: 'Прошивка', value: info.firmwareVersion ?? '—'),
            _InfoRow(
              label: 'Аппаратная версия',
              value: info.hardwareVersion ?? '—',
            ),
            _InfoRow(
              label: 'Дисплей',
              value: info.displayIsColor == null
                  ? '—'
                  : info.displayIsColor!
                  ? 'Цветной (81 RG)'
                  : '16 градаций серого',
            ),
            _InfoRow(label: 'Серийный номер', value: info.serialNumber ?? '—'),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 132,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colorScheme.onPrimaryContainer),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: colorScheme.onPrimaryContainer,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// Live compass ribbon on the phone, optionally mirrored on the glasses.
class _CompassCard extends StatelessWidget {
  const _CompassCard({required this.controller});

  final GlassesController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = controller.compassHeading;
    final active = controller.compassActive;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Компас', style: theme.textTheme.titleMedium),
                ),
                if (active) const _Pill(icon: Icons.explore, label: 'На очках'),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'HUD-лента с буквами N / NE / E / SE / S / SW / W / NW '
              'следует за компасом телефона. На очки уходит не чаще '
              'одного раза в секунду.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            CompassRibbon(heading: heading),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    heading == null
                        ? 'Ожидание датчика…'
                        : '${compassLabel(heading)} · ${compassDegrees(heading)}°',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: controller.connected
                      ? (active
                            ? controller.stopCompass
                            : controller.startCompass)
                      : null,
                  icon: Icon(active ? Icons.visibility_off : Icons.explore),
                  label: Text(active ? 'Скрыть с очков' : 'Показать на очках'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorShowCard extends StatelessWidget {
  const _ColorShowCard({required this.controller});

  final GlassesController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = controller.connected && controller.isColorCapable;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Демо цвета и анимации',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (controller.isAnimating)
                  _Pill(
                    icon: Icons.play_arrow,
                    label: controller.colorShowMode?.label ?? 'Воспроизведение',
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(switch (controller.colorShowMode) {
              ColorShowMode.sweep =>
                'Инкрементальная заливка: 2 команды на кадр (color + arc), '
                    'без перерисовки всего экрана — самая дешёвая плавная анимация.',
              ColorShowMode.pulse =>
                'Концентрические кольца: полная перерисовка экрана каждый кадр '
                    '(17 команд).',
              ColorShowMode.counter =>
                'Счётчик: одна короткая команда txtColor на кадр внутри '
                    'hold → clear → flush. Графических команд нет.',
              null =>
                'Полноэкранная анимация 304×256. «Экономная заливка» добавляет '
                    'лишь один сегмент дуги за кадр.',
            }, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.speed, size: 20),
                Expanded(
                  child: Slider(
                    value: controller.colorShowFps.toDouble(),
                    min: GlassesController.minColorShowFps.toDouble(),
                    max: GlassesController.maxColorShowFps.toDouble(),
                    divisions:
                        GlassesController.maxColorShowFps -
                        GlassesController.minColorShowFps,
                    label: '${controller.colorShowFps} кадр/с',
                    onChanged: enabled
                        ? (value) => controller.setColorShowSpeed(value.round())
                        : null,
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    '${controller.colorShowFps} кадр/с',
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
            if (controller.lastFrameBytes > 0)
              Text(
                '${controller.lastFrameBytes} Б/кадр · '
                '${(controller.colorShowBytesPerSecond / 1024).toStringAsFixed(2)} '
                'КБ/с при ${controller.colorShowFps} кадр/с',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final mode in ColorShowMode.values)
                  FilledButton.tonalIcon(
                    onPressed: enabled
                        ? () => controller.startColorShow(mode)
                        : null,
                    icon: Icon(switch (mode) {
                      ColorShowMode.pulse => Icons.blur_circular,
                      ColorShowMode.sweep => Icons.rotate_right,
                      ColorShowMode.counter => Icons.numbers,
                    }),
                    label: Text(mode.label),
                  ),
                OutlinedButton.icon(
                  onPressed: enabled && controller.isAnimating
                      ? controller.stopColorShow
                      : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('Стоп'),
                ),
              ],
            ),
            if (!controller.isColorCapable) ...[
              const SizedBox(height: 8),
              Text(
                'Цветные команды (0x3D/0x3E) требуют аппаратуру MDP08. Эти очки '
                'сообщают о дисплее с 16 градациями серого, поэтому демо недоступно.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

  static const List<({int value, String label})> _colors = [
    (value: ActiveLookColor.bright, label: 'Белый'),
    (value: ActiveLookColor.green, label: 'Зелёный'),
    (value: ActiveLookColor.orange, label: 'Янтарный'),
    (value: ActiveLookColor.red, label: 'Красный'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (final entry in _colors)
          ChoiceChip(
            label: Text(entry.label),
            avatar: CircleAvatar(
              backgroundColor: Color(paletteColor(entry.value)),
              radius: 8,
            ),
            selected: selected == entry.value,
            onSelected: (_) => onSelected(entry.value),
          ),
      ],
    );
  }
}

class _LumaSlider extends StatefulWidget {
  const _LumaSlider({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  State<_LumaSlider> createState() => _LumaSliderState();
}

class _LumaSliderState extends State<_LumaSlider> {
  late double _value = widget.value.toDouble();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.brightness_6_outlined, size: 20),
        Expanded(
          child: Slider(
            value: _value,
            min: 0,
            max: 15,
            divisions: 15,
            label: _value.round().toString(),
            onChanged: widget.enabled
                ? (value) => setState(() => _value = value)
                : null,
            onChangeEnd: widget.enabled
                ? (value) => widget.onChanged(value.round())
                : null,
          ),
        ),
        SizedBox(
          width: 24,
          child: Text(_value.round().toString(), textAlign: TextAlign.end),
        ),
      ],
    );
  }
}
