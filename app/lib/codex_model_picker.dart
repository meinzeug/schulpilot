import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

class CodexModel {
  final String id, name, defaultReasoning;
  final List<String> reasoningEfforts, inputModalities;
  final bool hidden;

  const CodexModel({
    required this.id,
    required this.name,
    required this.defaultReasoning,
    required this.reasoningEfforts,
    required this.inputModalities,
    required this.hidden,
  });

  static CodexModel fromJson(Json value) {
    final id = value['id'];
    final name = value['name'];
    final efforts = value['reasoning_efforts'];
    final defaultEffort = value['default_reasoning_effort'];
    final modalities = value['input_modalities'];
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        name.isEmpty ||
        efforts is! List ||
        efforts.any((value) => value is! String || value.isEmpty) ||
        defaultEffort is! String ||
        defaultEffort.isEmpty ||
        (efforts.isNotEmpty && !efforts.contains(defaultEffort)) ||
        modalities is! List ||
        modalities.any((value) => value is! String || value.isEmpty) ||
        value['hidden'] is! bool) {
      throw ApiError('Die Modellliste ist unvollständig. Bitte neu laden.');
    }
    return CodexModel(
      id: id,
      name: name,
      defaultReasoning: defaultEffort,
      reasoningEfforts: efforts.cast<String>().toSet().toList(),
      inputModalities: modalities.cast<String>().toSet().toList(),
      hidden: value['hidden'],
    );
  }
}

/// Codex choices come exclusively from the authenticated worker catalog.
/// Loading never changes a saved route; only explicit selections may adapt
/// reasoning to the capabilities shared by the text and photo models.
class CodexModelPicker extends StatefulWidget {
  final Api api;
  final String endpoint;
  final TextEditingController model, extractionModel;
  final String reasoningEffort;
  final ValueChanged<String> onReasoningChanged;
  final Json savedConfig;

  const CodexModelPicker({
    super.key,
    required this.api,
    required this.endpoint,
    required this.model,
    required this.extractionModel,
    required this.reasoningEffort,
    required this.onReasoningChanged,
    required this.savedConfig,
  });

  @override
  State<CodexModelPicker> createState() => CodexModelPickerState();
}

class CodexModelPickerState extends State<CodexModelPicker> {
  List<CodexModel> models = [];
  bool loading = true, loaded = false;
  String? error, adjustment;
  int generation = 0;

  CodexModel? modelById(String id) {
    for (final model in models) {
      if (model.id == id) return model;
    }
    return null;
  }

  CodexModel? get lessonModel => modelById(widget.model.text);
  CodexModel? get photoModel => widget.extractionModel.text.isEmpty
      ? lessonModel
      : modelById(widget.extractionModel.text);

  List<String> get supportedEfforts {
    final lesson = lessonModel, photo = photoModel;
    if (lesson == null || photo == null) return [];
    return lesson.reasoningEfforts
        .where(photo.reasoningEfforts.contains)
        .toList();
  }

  bool get unchanged =>
      widget.savedConfig['provider'] == 'codex' &&
      widget.model.text == (widget.savedConfig['model'] ?? '') &&
      widget.extractionModel.text ==
          (widget.savedConfig['extraction_model'] ?? '') &&
      widget.reasoningEffort ==
          (widget.savedConfig['reasoning_effort'] ?? 'medium');

  String? get selectionError {
    if (loading) return 'Die Modellliste wird noch geladen.';
    if (!loaded || error != null) {
      return 'Bitte lade die Modellliste, bevor du eine andere Auswahl speicherst.';
    }
    if (lessonModel == null) {
      return 'Das gewählte Lernmodell ist nicht in der aktuellen Modellliste.';
    }
    if (!lessonModel!.inputModalities.contains('text')) {
      return 'Das Lernmodell muss Texte verarbeiten können.';
    }
    if (photoModel == null) {
      return 'Das gewählte Bildmodell ist nicht in der aktuellen Modellliste.';
    }
    if (!photoModel!.inputModalities.contains('image')) {
      return 'Dieses Modell kann keine Fotos lesen. Wähle ein Bildmodell.';
    }
    if (supportedEfforts.isEmpty) {
      return 'Diese Modelle haben keine gemeinsame Denkstufe. Wähle ein anderes Bildmodell.';
    }
    if (!supportedEfforts.contains(widget.reasoningEffort)) {
      return 'Bitte wähle eine Denkstufe, die beide Modelle unterstützen.';
    }
    return null;
  }

  void validateForSave() {
    // Keep an existing route editable during a worker outage. The backend
    // independently applies the same exception and checks every changed route.
    if (unchanged && (loading || !loaded || error != null)) return;
    final message = selectionError;
    if (message != null) throw ApiError(message);
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(CodexModelPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api || oldWidget.endpoint != widget.endpoint) {
      load();
    }
  }

  Future<void> load() async {
    final request = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final response = await widget.api.get('${widget.endpoint}/codex/models');
      if (!mounted || request != generation) return;
      final rows = response['models'];
      if (response['source'] != 'codex_cli' ||
          response['cli_version'] is! String ||
          rows is! List ||
          rows.isEmpty ||
          rows.any((row) => row is! Map)) {
        throw ApiError('Keine Modellliste verfügbar. Bitte neu laden.');
      }
      final parsed = rows
          .map((row) => CodexModel.fromJson(Json.from(row)))
          .toList();
      if (parsed.map((model) => model.id).toSet().length != parsed.length) {
        throw ApiError('Die Modellliste ist ungültig. Bitte neu laden.');
      }
      setState(() {
        models = parsed;
        loaded = true;
        loading = false;
      });
    } catch (failure) {
      if (!mounted || request != generation) return;
      setState(() {
        loading = false;
        error = failure is ApiError
            ? failure.message
            : 'Die Modellliste konnte nicht geladen werden.';
      });
    }
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  void chooseModel(String value, {bool photo = false}) {
    setState(() {
      if (photo) {
        widget.extractionModel.text = value;
      } else {
        widget.model.text = value;
      }
      adjustment = null;
      final efforts = supportedEfforts;
      if (efforts.isNotEmpty && !efforts.contains(widget.reasoningEffort)) {
        final lessonDefault = lessonModel!.defaultReasoning;
        final photoDefault = photoModel!.defaultReasoning;
        final next = efforts.contains(lessonDefault)
            ? lessonDefault
            : efforts.contains(photoDefault)
            ? photoDefault
            : efforts.first;
        adjustment =
            'Denkstufe auf $next angepasst; sie gilt für beide Modelle.';
        widget.onReasoningChanged(next);
      }
    });
  }

  String label(CodexModel model) =>
      '${model.name}${model.hidden ? ' · ausgeblendet' : ''}'
      '${model.reasoningEfforts.isEmpty ? ' · keine einstellbare Denkstufe' : ''}';

  Widget modelDropdown({bool photo = false}) {
    final value = photo ? widget.extractionModel.text : widget.model.text;
    final choices = photo
        ? models.where((model) => model.inputModalities.contains('image'))
        : models;
    final known = choices.any((model) => model.id == value);
    final items = <DropdownMenuItem<String>>[
      if (photo)
        const DropdownMenuItem(value: '', child: Text('Gleiches Modell')),
      for (final model in choices)
        DropdownMenuItem(
          value: model.id,
          enabled:
              model.reasoningEfforts.isNotEmpty &&
              (photo || model.inputModalities.contains('text')),
          child: Text(
            '${label(model)} (${model.id})',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      if (value.isNotEmpty && !known)
        DropdownMenuItem(
          value: value,
          enabled: false,
          child: Text(
            '$value · gespeichert',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ];
    return DropdownButtonFormField<String>(
      key: ValueKey('codex-${photo ? 'photo' : 'lesson'}-$value'),
      initialValue: value.isEmpty && !photo ? null : value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: photo ? 'Bildmodell' : 'Modell für Lerneinheiten',
      ),
      hint: const Text('Modell wählen'),
      items: items,
      onChanged: loading || !loaded || error != null
          ? null
          : (value) {
              if (value != null) chooseModel(value, photo: photo);
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    final efforts = supportedEfforts;
    final currentEffort = widget.reasoningEffort;
    final effortOptions = [
      ...efforts,
      if (currentEffort.isNotEmpty && !efforts.contains(currentEffort))
        currentEffort,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (loading) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          const Text('Codex-Modelle werden geladen …'),
          const SizedBox(height: 16),
        ],
        modelDropdown(),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          key: ValueKey('codex-reasoning-$currentEffort'),
          initialValue: currentEffort.isEmpty ? null : currentEffort,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Reasoning / Denkstufe'),
          items: [
            for (final effort in effortOptions)
              DropdownMenuItem(
                value: effort,
                enabled: efforts.contains(effort),
                child: Text(
                  '$effort${efforts.contains(effort) ? '' : ' · gespeichert'}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: loading || !loaded || error != null || efforts.isEmpty
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() => adjustment = null);
                  widget.onReasoningChanged(value);
                },
        ),
        if (adjustment != null) ...[
          const SizedBox(height: 8),
          Text(adjustment!, style: const TextStyle(color: muted)),
        ],
        const SizedBox(height: 16),
        modelDropdown(photo: true),
        const SizedBox(height: 12),
        if (error != null) Notice(error!, warning: true),
        if (!loading && selectionError != null)
          Notice(
            unchanged
                ? 'Gespeicherte Auswahl bleibt erhalten. ${selectionError!}'
                : selectionError!,
            warning: true,
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: loading ? null : load,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Modelle neu laden'),
          ),
        ),
        const Text(
          'Modellzugriff wird mit dem Prüflauf bestätigt.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ],
    );
  }
}
