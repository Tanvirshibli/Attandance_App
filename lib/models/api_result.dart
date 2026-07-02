class ApiResult<T> {
  const ApiResult({
    required this.success,
    this.data,
    this.message,
    this.statusCode,
  });

  final bool success;
  final T? data;
  final String? message;
  final int? statusCode;

  factory ApiResult.ok(T data, {String? message, int? statusCode}) {
    return ApiResult(
      success: true,
      data: data,
      message: message,
      statusCode: statusCode,
    );
  }

  factory ApiResult.fail(String message, {int? statusCode}) {
    return ApiResult(
      success: false,
      message: message,
      statusCode: statusCode,
    );
  }
}
