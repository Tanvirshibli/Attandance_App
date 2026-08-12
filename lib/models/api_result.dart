class ApiResult<T> {
  const ApiResult({
    required this.success,
    this.data,
    this.message,
    this.detail,
    this.statusCode,
    this.isSetupIssue = false,
  });

  final bool success;
  final T? data;
  final String? message;
  /// Secondary line (context, action hint, etc.).
  final String? detail;
  final int? statusCode;
  final bool isSetupIssue;

  factory ApiResult.ok(T data, {String? message, int? statusCode}) {
    return ApiResult(
      success: true,
      data: data,
      message: message,
      statusCode: statusCode,
    );
  }

  factory ApiResult.fail(
    String message, {
    int? statusCode,
    String? detail,
    bool isSetupIssue = false,
  }) {
    return ApiResult(
      success: false,
      message: message,
      detail: detail,
      statusCode: statusCode,
      isSetupIssue: isSetupIssue,
    );
  }
}
