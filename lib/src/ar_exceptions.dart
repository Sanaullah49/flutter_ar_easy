/// Base exception for all AR-related errors.
class ArException implements Exception {
  final String message;
  final String? code;
  final dynamic details;

  const ArException(this.message, {this.code, this.details});

  @override
  String toString() => 'ArException($code): $message';
}

class ArNotSupportedException extends ArException {
  const ArNotSupportedException([
    super.message = 'AR is not supported on this device',
  ]) : super(code: 'AR_NOT_SUPPORTED');
}

class ArSessionException extends ArException {
  const ArSessionException(super.message) : super(code: 'SESSION_ERROR');
}

class ArModelException extends ArException {
  const ArModelException(super.message) : super(code: 'MODEL_ERROR');
}

class ArPermissionException extends ArException {
  const ArPermissionException([super.message = 'Camera permission denied'])
    : super(code: 'PERMISSION_DENIED');
}

class ArPlatformException extends ArException {
  const ArPlatformException(super.message) : super(code: 'PLATFORM_ERROR');
}
