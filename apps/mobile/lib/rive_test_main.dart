import 'package:flutter/material.dart';
import 'package:rive/rive.dart';

void main() {
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: RiveTestScreen(),
    ),
  );
}

const List<_RivAsset> _assets = [
  _RivAsset('dinner', 'assets/rive/dinner.riv'),
  _RivAsset('focus', 'assets/rive/focus.riv'),
  _RivAsset('ghost', 'assets/rive/ghost.riv'),
  _RivAsset('grassResting', 'assets/rive/grassResting.riv'),
  _RivAsset('sofaTikTok', 'assets/rive/sofaTikTok.riv'),
  _RivAsset('pause', 'assets/rive/pause.riv'),
  _RivAsset('head', 'assets/rive/head.riv'),
  _RivAsset('full_body', 'assets/rive/full_body.riv'),
];

class _RivAsset {
  final String label;
  final String path;
  const _RivAsset(this.label, this.path);
}

class RiveTestScreen extends StatefulWidget {
  const RiveTestScreen({super.key});

  @override
  State<RiveTestScreen> createState() => _RiveTestScreenState();
}

final class _SpeedRiveController extends RiveWidgetController {
  _SpeedRiveController(super.file, {super.stateMachineSelector});

  double speedMultiplier = 1.0;

  @override
  bool advance(double elapsedSeconds) =>
      super.advance(elapsedSeconds * speedMultiplier);
}

const List<double> _speedPresets = [0.25, 0.5, 1.0, 1.5, 2.0, 3.0];

class _RiveTestScreenState extends State<RiveTestScreen> {
  int _index = 0;
  double _speed = 1.0;
  File? _file;
  _SpeedRiveController? _controller;
  ViewModelInstance? _vmi;
  List<ViewModelProperty> _props = const [];
  Map<String, List<String>> _enumValuesByType = const {};
  List<String> _stateMachineNames = const [];
  String? _activeStateMachine;
  String? _error;
  int _reloadKey = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _disposeCurrent();
    super.dispose();
  }

  void _disposeCurrent() {
    _controller?.dispose();
    _file?.dispose();
    _controller = null;
    _file = null;
    _vmi = null;
    _props = const [];
    _enumValuesByType = const {};
    _stateMachineNames = const [];
    _activeStateMachine = null;
  }

  Future<void> _load({String? stateMachineName}) async {
    final asset = _assets[_index];
    setState(() {
      _disposeCurrent();
      _error = null;
    });
    try {
      final file = await File.asset(asset.path, riveFactory: Factory.rive);
      if (file == null) {
        if (!mounted) return;
        setState(() => _error = 'File.asset returned null for ${asset.path}');
        return;
      }
      final controller = _SpeedRiveController(
        file,
        stateMachineSelector: stateMachineName != null
            ? StateMachineNamed(stateMachineName)
            : const StateMachineDefault(),
      )..speedMultiplier = _speed;
      final vmi = controller.dataBind(DataBind.auto());
      final enums = <String, List<String>>{
        for (final e in file.enums) e.name: e.values,
      };
      final ab = controller.artboard;
      final smNames = <String>[
        for (var i = 0; i < ab.stateMachineCount(); i++)
          ab.stateMachineAt(i)?.name ?? 'sm_$i',
      ];
      if (!mounted) {
        controller.dispose();
        file.dispose();
        return;
      }
      setState(() {
        _file = file;
        _controller = controller;
        _vmi = vmi;
        _props = List<ViewModelProperty>.from(vmi.properties);
        _enumValuesByType = enums;
        _stateMachineNames = smNames;
        _activeStateMachine = controller.stateMachine.name;
        _reloadKey++;
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _error = '$e\n$st');
    }
  }

  void _switchTo(int i) {
    if (i == _index) return;
    setState(() => _index = i);
    _load();
  }

  void _switchStateMachine(String name) {
    if (name == _activeStateMachine) return;
    _load(stateMachineName: name);
  }

  @override
  Widget build(BuildContext context) {
    final asset = _assets[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _AssetPicker(
              assets: _assets,
              currentIndex: _index,
              onPick: _switchTo,
              onReload: () => _load(stateMachineName: _activeStateMachine),
            ),
            Container(
              color: const Color(0xFF161616),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  const Text(
                    'Speed:',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final s in _speedPresets) ...[
                            ChoiceChip(
                              label: Text('${s}x'),
                              selected: (s - _speed).abs() < 0.001,
                              onSelected: (_) {
                                setState(() => _speed = s);
                                _controller?.speedMultiplier = s;
                              },
                              selectedColor: Colors.indigo,
                              backgroundColor: const Color(0xFF2A2A2A),
                              labelStyle: TextStyle(
                                color: (s - _speed).abs() < 0.001
                                    ? Colors.white
                                    : Colors.white70,
                                fontSize: 12,
                              ),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                            const SizedBox(width: 6),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_stateMachineNames.isNotEmpty)
              Container(
                color: const Color(0xFF161616),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    const Text(
                      'SM:',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButton<String>(
                        value: _activeStateMachine,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF1F1F1F),
                        style: const TextStyle(color: Colors.white),
                        items: [
                          for (final n in _stateMachineNames)
                            DropdownMenuItem(value: n, child: Text(n)),
                        ],
                        onChanged: (n) {
                          if (n != null) _switchStateMachine(n);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _controller != null
                        ? RiveWidget(
                            key: ValueKey(_reloadKey),
                            controller: _controller!,
                            fit: Fit.contain,
                          )
                        : Center(
                            child: _error != null
                                ? Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: SingleChildScrollView(
                                      child: Text(
                                        _error!,
                                        style: const TextStyle(
                                          color: Colors.red,
                                        ),
                                      ),
                                    ),
                                  )
                                : const CircularProgressIndicator(),
                          ),
                  ),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        asset.path,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.45,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFF111111),
                border: Border(top: BorderSide(color: Colors.white12)),
              ),
              child: _vmi == null
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'No ViewModel bound',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : _PropertyList(
                      vmi: _vmi!,
                      props: _props,
                      enumValuesByType: _enumValuesByType,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssetPicker extends StatelessWidget {
  final List<_RivAsset> assets;
  final int currentIndex;
  final ValueChanged<int> onPick;
  final VoidCallback onReload;
  const _AssetPicker({
    required this.assets,
    required this.currentIndex,
    required this.onPick,
    required this.onReload,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < assets.length; i++) ...[
                    ChoiceChip(
                      label: Text(assets[i].label),
                      selected: i == currentIndex,
                      onSelected: (_) => onPick(i),
                      selectedColor: Colors.indigo,
                      backgroundColor: const Color(0xFF2A2A2A),
                      labelStyle: TextStyle(
                        color: i == currentIndex
                            ? Colors.white
                            : Colors.white70,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: onReload,
            icon: const Icon(Icons.refresh, color: Colors.white70),
            tooltip: 'Reload',
          ),
        ],
      ),
    );
  }
}

class _PropertyList extends StatelessWidget {
  final ViewModelInstance vmi;
  final List<ViewModelProperty> props;
  final Map<String, List<String>> enumValuesByType;
  const _PropertyList({
    required this.vmi,
    required this.props,
    required this.enumValuesByType,
  });

  @override
  Widget build(BuildContext context) {
    if (props.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'ViewModel has no properties',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: props.length,
      separatorBuilder: (_, __) => const Divider(color: Colors.white12),
      itemBuilder: (ctx, i) {
        final p = props[i];
        return _PropertyRow(
          property: p,
          vmi: vmi,
          enumValuesByType: enumValuesByType,
        );
      },
    );
  }
}

class _PropertyRow extends StatefulWidget {
  final ViewModelProperty property;
  final ViewModelInstance vmi;
  final Map<String, List<String>> enumValuesByType;
  const _PropertyRow({
    required this.property,
    required this.vmi,
    required this.enumValuesByType,
  });

  @override
  State<_PropertyRow> createState() => _PropertyRowState();
}

class _PropertyRowState extends State<_PropertyRow> {
  @override
  Widget build(BuildContext context) {
    final p = widget.property;
    final header = Row(
      children: [
        Expanded(
          child: Text(
            p.name,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          p.type.name,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
      ],
    );

    Widget control;
    switch (p.type) {
      case DataType.color:
        control = _buildColor();
        break;
      case DataType.number:
      case DataType.integer:
        control = _buildNumber(isInt: p.type == DataType.integer);
        break;
      case DataType.boolean:
        control = _buildBoolean();
        break;
      case DataType.string:
        control = _buildString();
        break;
      case DataType.trigger:
        control = _buildTrigger();
        break;
      case DataType.enumType:
        control = _buildEnum();
        break;
      default:
        control = Text(
          'unsupported (${p.type.name})',
          style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
        );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [header, const SizedBox(height: 6), control],
    );
  }

  Widget _buildColor() {
    final prop = widget.vmi.color(widget.property.name);
    if (prop == null) return _missing();
    final current = prop.value;
    return Row(
      children: [
        GestureDetector(
          onTap: () async {
            final picked = await showDialog<Color>(
              context: context,
              builder: (_) => _ColorPickerDialog(initial: current),
            );
            if (picked != null) {
              prop.value = picked;
              setState(() {});
            }
          },
          child: Container(
            width: 48,
            height: 32,
            decoration: BoxDecoration(
              color: current,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white24),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '#${current.toARGB32().toRadixString(16).padLeft(8, "0").toUpperCase()}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildNumber({required bool isInt}) {
    final prop = widget.vmi.number(widget.property.name);
    if (prop == null) return _missing();
    final v = prop.value;
    final lower = v < 0 ? v - 100 : 0.0;
    final upper = v > 100 ? v + 100 : 100.0;
    return Row(
      children: [
        Expanded(
          child: Slider(
            min: lower,
            max: upper,
            value: v.clamp(lower, upper).toDouble(),
            onChanged: (nv) {
              prop.value = isInt ? nv.roundToDouble() : nv;
              setState(() {});
            },
          ),
        ),
        SizedBox(
          width: 64,
          child: Text(
            isInt ? v.round().toString() : v.toStringAsFixed(2),
            textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildBoolean() {
    final prop = widget.vmi.boolean(widget.property.name);
    if (prop == null) return _missing();
    return Align(
      alignment: Alignment.centerLeft,
      child: Switch(
        value: prop.value,
        onChanged: (nv) {
          prop.value = nv;
          setState(() {});
        },
      ),
    );
  }

  Widget _buildString() {
    final prop = widget.vmi.string(widget.property.name);
    if (prop == null) return _missing();
    return TextField(
      controller: TextEditingController(text: prop.value)
        ..selection = TextSelection.collapsed(offset: prop.value.length),
      style: const TextStyle(color: Colors.white),
      decoration: const InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Color(0xFF222222),
        border: OutlineInputBorder(borderSide: BorderSide.none),
      ),
      onSubmitted: (nv) {
        prop.value = nv;
        setState(() {});
      },
    );
  }

  Widget _buildTrigger() {
    final prop = widget.vmi.trigger(widget.property.name);
    if (prop == null) return _missing();
    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.icon(
        onPressed: () => prop.trigger(),
        icon: const Icon(Icons.bolt),
        label: const Text('Fire trigger'),
      ),
    );
  }

  Widget _buildEnum() {
    final prop = widget.vmi.enumerator(widget.property.name);
    if (prop == null) return _missing();
    final values = widget.enumValuesByType[prop.enumType] ?? const <String>[];
    final current = prop.value;
    if (values.isEmpty) {
      return Text(
        'enum "${prop.enumType}" — current: $current (no values metadata)',
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      );
    }
    return DropdownButton<String>(
      value: values.contains(current) ? current : null,
      hint: Text(current, style: const TextStyle(color: Colors.white70)),
      isExpanded: true,
      dropdownColor: const Color(0xFF1F1F1F),
      style: const TextStyle(color: Colors.white),
      items: [
        for (final v in values) DropdownMenuItem(value: v, child: Text(v)),
      ],
      onChanged: (nv) {
        if (nv == null) return;
        prop.value = nv;
        setState(() {});
      },
    );
  }

  Widget _missing() => const Text(
    'property not found at runtime',
    style: TextStyle(color: Colors.redAccent, fontSize: 12),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  final Color initial;
  const _ColorPickerDialog({required this.initial});

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late double r, g, b, a;

  @override
  void initState() {
    super.initState();
    r = widget.initial.r * 255;
    g = widget.initial.g * 255;
    b = widget.initial.b * 255;
    a = widget.initial.a * 255;
  }

  Color get _current =>
      Color.fromARGB(a.round(), r.round(), g.round(), b.round());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pick color'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 60,
              decoration: BoxDecoration(
                color: _current,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.black26),
              ),
            ),
            const SizedBox(height: 12),
            _slider('R', r, Colors.red, (v) => setState(() => r = v)),
            _slider('G', g, Colors.green, (v) => setState(() => g = v)),
            _slider('B', b, Colors.blue, (v) => setState(() => b = v)),
            _slider('A', a, Colors.grey, (v) => setState(() => a = v)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final preset in const [
                  Color(0xFFE74C3C),
                  Color(0xFF2ECC71),
                  Color(0xFF3498DB),
                  Color(0xFFF1C40F),
                  Color(0xFF9B59B6),
                  Color(0xFFE67E22),
                  Color(0xFF1ABC9C),
                  Color(0xFFECF0F1),
                  Color(0xFF34495E),
                  Color(0xFF000000),
                ])
                  GestureDetector(
                    onTap: () => setState(() {
                      r = preset.r * 255;
                      g = preset.g * 255;
                      b = preset.b * 255;
                      a = preset.a * 255;
                    }),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: preset,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.black26),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_current),
          child: const Text('OK'),
        ),
      ],
    );
  }

  Widget _slider(
    String label,
    double value,
    Color color,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(width: 16, child: Text(label)),
        Expanded(
          child: Slider(
            value: value,
            min: 0,
            max: 255,
            activeColor: color,
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 36, child: Text(value.round().toString())),
      ],
    );
  }
}
