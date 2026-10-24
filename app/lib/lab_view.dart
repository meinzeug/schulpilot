import 'dart:convert';

import 'api.dart';
import 'lab_recipe.dart';

/// A finite technical display state. Values describe a local experiment, never
/// a student's answer or a claim that the source contains the explored values.
class LabView {
  static const sentenceOrders = [
    'mira_time_book',
    'time_mira_book',
    'book_mira_time',
    'mira_book_time',
  ];
  static const groups = {'mira', 'verb', 'morning', 'book'};

  static Object? decode(Object? raw) {
    if (raw is String) {
      if (raw.runes.length > 512) {
        return null;
      }
      try {
        return jsonDecode(raw);
      } catch (_) {
        return null;
      }
    }
    return raw;
  }

  static Json? force(Object? raw, ForceLabModel original) {
    final value = decode(raw);
    const keys = {
      'version',
      'recipe_id',
      'recipe_version',
      'mass_kg',
      'acceleration_m_s2',
      'time_ms',
    };
    if (value is! Map ||
        value.length != keys.length ||
        value.keys.toSet().difference(keys).isNotEmpty ||
        value['version'] is! int ||
        value['version'] != 1 ||
        value['recipe_version'] is! int ||
        value['recipe_version'] != 1 ||
        value['recipe_id'] != 'physics.force_motion') {
      return null;
    }
    final mass = value['mass_kg'],
        acceleration = value['acceleration_m_s2'],
        time = value['time_ms'];
    if (mass is! num ||
        acceleration is! num ||
        !mass.isFinite ||
        !acceleration.isFinite ||
        mass < .5 ||
        mass > 10 ||
        acceleration < 0 ||
        acceleration > 4 ||
        (mass != original.massKg && (mass * 2).roundToDouble() != mass * 2) ||
        (acceleration != original.acceleration &&
            (acceleration * 4).roundToDouble() != acceleration * 4) ||
        time is! int ||
        time < 0 ||
        time > 2000 ||
        time % 50 != 0) {
      return null;
    }
    return forceState(mass.toDouble(), acceleration.toDouble(), time);
  }

  static Json forceState(double mass, double acceleration, int timeMs) => {
    'version': 1,
    'recipe_id': 'physics.force_motion',
    'recipe_version': 1,
    'mass_kg': mass,
    'acceleration_m_s2': acceleration,
    'time_ms': timeMs,
  };

  static Json? sentence(Object? raw) {
    final value = decode(raw);
    const keys = {
      'version',
      'recipe_id',
      'recipe_version',
      'order_id',
      'selected_group',
      'split_example',
    };
    if (value is! Map ||
        value.length != keys.length ||
        value.keys.toSet().difference(keys).isNotEmpty ||
        value['version'] is! int ||
        value['version'] != 1 ||
        value['recipe_version'] is! int ||
        value['recipe_version'] != 1 ||
        value['recipe_id'] != 'german.sentence_shift' ||
        !sentenceOrders.contains(value['order_id']) ||
        !groups.contains(value['selected_group']) ||
        value['split_example'] is! bool) {
      return null;
    }
    return sentenceState(
      sentenceOrders.indexOf(value['order_id']),
      value['selected_group'],
      value['split_example'],
    );
  }

  static Json sentenceState(int order, String group, bool split) => {
    'version': 1,
    'recipe_id': 'german.sentence_shift',
    'recipe_version': 1,
    'order_id': sentenceOrders[order],
    'selected_group': group,
    'split_example': split,
  };

  static Json? checked(Object? raw, Json block) {
    if (block['kind'] != 'lab') {
      return null;
    }
    final recipe = LabRecipe.read(block['lab']);
    if (recipe?.force != null) {
      return force(raw, recipe!.force!);
    }
    if (recipe?.sentenceExample != null) {
      return sentence(raw);
    }
    return null;
  }

  static String encoded(Json value) => jsonEncode(value);
}
