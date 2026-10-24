/// A finite, app-owned recipe contract. Provider output supplies only bounded
/// physical parameters: never coordinates, callbacks, assets, units or code.
class LabRecipe {
  final String id;
  final int version;
  final ForceLabModel? force;
  final String? sentenceExample;
  const LabRecipe._(this.id, this.version, {this.force, this.sentenceExample});

  static LabRecipe? read(Object? raw) {
    if (raw is! Map ||
        raw.keys.toSet().difference({
          'version',
          'recipe_id',
          'recipe_version',
          'parameters',
        }).isNotEmpty ||
        raw.length != 4 ||
        raw['version'] is! int ||
        raw['version'] != 1 ||
        raw['recipe_version'] is! int ||
        raw['recipe_version'] != 1) {
      return null;
    }
    final parameters = raw['parameters'];
    if (raw['recipe_id'] == 'german.sentence_shift') {
      if (parameters is! Map ||
          parameters.length != 1 ||
          parameters['example_id'] != 'mira_reads') {
        return null;
      }
      return const LabRecipe._(
        'german.sentence_shift',
        1,
        sentenceExample: 'mira_reads',
      );
    }
    if (raw['recipe_id'] != 'physics.force_motion') {
      return null;
    }
    if (parameters is! Map ||
        parameters.length != 2 ||
        parameters.keys.toSet().difference({
          'mass_kg',
          'acceleration_m_s2',
        }).isNotEmpty) {
      return null;
    }
    final mass = parameters['mass_kg'],
        acceleration = parameters['acceleration_m_s2'];
    if (mass is! num ||
        acceleration is! num ||
        !mass.isFinite ||
        !acceleration.isFinite ||
        mass < .5 ||
        mass > 10 ||
        acceleration < 0 ||
        acceleration > 4) {
      return null;
    }
    return LabRecipe._(
      'physics.force_motion',
      1,
      force: ForceLabModel(
        massKg: mass.toDouble(),
        acceleration: acceleration.toDouble(),
      ),
    );
  }
}

/// Translation of the centre of mass, from rest with constant resultant force.
/// No collision, friction, rolling inertia or student evaluation is modelled.
class ForceLabModel {
  static const durationSeconds = 2.0;
  static const trackMetres = 8.0;
  final double massKg, acceleration;
  const ForceLabModel({required this.massKg, required this.acceleration});
  double get forceNewtons => massKg * acceleration;
  double distance(double seconds) {
    final t = seconds.clamp(0.0, durationSeconds);
    return .5 * acceleration * t * t;
  }

  double velocity(double seconds) =>
      acceleration * seconds.clamp(0.0, durationSeconds);
  double progress(double seconds) =>
      (distance(seconds) / trackMetres).clamp(0.0, 1.0);
  ForceLabModel copyWith({double? massKg, double? acceleration}) =>
      ForceLabModel(
        massKg: massKg ?? this.massKg,
        acceleration: acceleration ?? this.acceleration,
      );
}
