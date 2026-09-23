enum ValidationSeverity {
  /// The pack cannot be loaded as it stands.
  error,

  /// The pack loads, but an adult should look at it before a session.
  warning,
}

/// One problem found while validating a sound pack.
class ValidationIssue {
  const ValidationIssue(this.severity, this.message, {this.subject});

  const ValidationIssue.error(String message, {String? subject})
    : this(ValidationSeverity.error, message, subject: subject);

  const ValidationIssue.warning(String message, {String? subject})
    : this(ValidationSeverity.warning, message, subject: subject);
  final ValidationSeverity severity;

  /// Adult-facing sentence, ready to show in the adult area.
  final String message;

  /// The sound or word the problem belongs to, when there is one.
  final String? subject;

  bool get isError => severity == ValidationSeverity.error;

  @override
  String toString() => '${severity.name}: $message';
}

/// The outcome of validating a sound pack.
class ValidationResult {
  const ValidationResult(this.issues);

  const ValidationResult.ok() : issues = const [];
  final List<ValidationIssue> issues;

  List<ValidationIssue> get errors =>
      issues.where((issue) => issue.isError).toList();

  List<ValidationIssue> get warnings =>
      issues.where((issue) => !issue.isError).toList();

  /// A pack with warnings still loads. A pack with errors does not.
  bool get isValid => errors.isEmpty;

  bool get hasWarnings => warnings.isNotEmpty;
}
