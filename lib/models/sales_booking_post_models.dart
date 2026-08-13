class DeliveryDetailInput {
  const DeliveryDetailInput({
    this.name,
    this.phone,
    this.roadNo,
    this.address,
    this.productDetails,
  });

  final String? name;
  final String? phone;
  final String? roadNo;
  final String? address;
  final String? productDetails;

  void applyTo(Map<String, String> fields, int index) {
    final prefix = 'deliveryDetails[$index]';
    _put(fields, '$prefix[name]', name);
    _put(fields, '$prefix[phone]', phone);
    _put(fields, '$prefix[roadNo]', roadNo);
    _put(fields, '$prefix[address]', address);
    _put(fields, '$prefix[productDetails]', productDetails);
  }

  static void _put(Map<String, String> fields, String key, String? value) {
    final trimmed = value?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      fields[key] = trimmed;
    }
  }
}

class BookingLineInput {
  const BookingLineInput({
    required this.productId,
    required this.unitId,
    required this.qty,
    required this.price,
    this.note,
    this.cdPriceId,
    this.mrp,
    this.settingIds = const [],
    this.flockIds = const [],
  });

  final int productId;
  final int unitId;
  final double qty;
  final double price;
  final String? note;
  final int? cdPriceId;
  final double? mrp;
  final List<int> settingIds;
  final List<int> flockIds;

  void applyTo(Map<String, String> fields, int index) {
    final prefix = 'details[$index]';
    fields['$prefix[productId]'] = '$productId';
    fields['$prefix[unitId]'] = '$unitId';
    fields['$prefix[qty]'] = _num(qty);
    fields['$prefix[price]'] = _num(price);
    final lineNote = note?.trim();
    if (lineNote != null && lineNote.isNotEmpty) {
      fields['$prefix[note]'] = lineNote;
    }
    if (cdPriceId != null && cdPriceId! > 0) {
      fields['$prefix[cdPriceId]'] = '$cdPriceId';
    }
    if (mrp != null) {
      fields['$prefix[mrp]'] = _num(mrp!);
    }
    for (var j = 0; j < settingIds.length; j++) {
      fields['$prefix[settingIds][$j]'] = '${settingIds[j]}';
    }
    for (var j = 0; j < flockIds.length; j++) {
      fields['$prefix[flockIds][$j]'] = '${flockIds[j]}';
    }
  }

  static String _num(num value) {
    if (value == value.roundToDouble()) {
      return value.round().toString();
    }
    return value.toString();
  }
}

class CreateBookingPersonBookRequest {
  const CreateBookingPersonBookRequest({
    required this.module,
    required this.dealerId,
    required this.categoryId,
    required this.subCategoryId,
    required this.childCategoryId,
    required this.bookingPointId,
    required this.bookingPerson,
    required this.bookingType,
    required this.isBookingMoney,
    required this.isMultiDelivery,
    required this.discount,
    required this.discountType,
    required this.advanceAmount,
    required this.totalAmount,
    required this.bookingDate,
    required this.invoiceDate,
    required this.lines,
    this.cZoneId,
    this.chicksPriceId,
    this.commissionId,
    this.note,
    this.deliveryDetails = const [],
  });

  final String module;
  final int dealerId;
  final int categoryId;
  final int subCategoryId;
  final int childCategoryId;
  final int bookingPointId;
  final int bookingPerson;
  final String bookingType;
  final bool isBookingMoney;
  final bool isMultiDelivery;
  final double discount;
  final String discountType;
  final double advanceAmount;
  final double totalAmount;
  final String bookingDate;
  final String invoiceDate;
  final List<BookingLineInput> lines;
  final int? cZoneId;
  final int? chicksPriceId;
  final int? commissionId;
  final String? note;
  final List<DeliveryDetailInput> deliveryDetails;

  Map<String, String> toFormFields() {
    final fields = <String, String>{
      'module': module,
      'dealerId': '$dealerId',
      'categoryId': '$categoryId',
      'subCategoryId': '$subCategoryId',
      'childCategoryId': '$childCategoryId',
      'bookingPointId': '$bookingPointId',
      'bookingPerson': '$bookingPerson',
      'bookingType': bookingType,
      'isBookingMoney': isBookingMoney ? '1' : '0',
      'isMultiDelivery': isMultiDelivery ? '1' : '0',
      'discount': _num(discount),
      'discountType': discountType,
      'advanceAmount': _num(advanceAmount),
      'totalAmount': _num(totalAmount),
      'bookingDate': bookingDate,
      'invoiceDate': invoiceDate,
    };

    if (module == 'chicks' && cZoneId != null && cZoneId! > 0) {
      fields['cZoneId'] = '$cZoneId';
    }
    if (chicksPriceId != null && chicksPriceId! > 0) {
      fields['chicksPriceId'] = '$chicksPriceId';
    }
    if (commissionId != null && commissionId! > 0) {
      fields['commissionId'] = '$commissionId';
    }
    final trimmedNote = note?.trim();
    if (trimmedNote != null && trimmedNote.isNotEmpty) {
      fields['note'] = trimmedNote;
    }

    for (var i = 0; i < lines.length; i++) {
      lines[i].applyTo(fields, i);
    }

    if (module == 'chicks') {
      for (var i = 0; i < deliveryDetails.length; i++) {
        deliveryDetails[i].applyTo(fields, i);
      }
    }

    return fields;
  }

  static String _num(num value) {
    if (value == value.roundToDouble()) {
      return value.round().toString();
    }
    return value.toString();
  }
}

class BookingPersonBookCreated {
  const BookingPersonBookCreated({
    required this.module,
    required this.id,
    required this.bookingNo,
    required this.status,
    required this.totalAmount,
    this.message,
  });

  final String module;
  final int id;
  final String bookingNo;
  final String status;
  final double totalAmount;
  final String? message;

  factory BookingPersonBookCreated.fromJson(Map<String, dynamic> json) {
    return BookingPersonBookCreated(
      module: (json['module'] ?? '').toString(),
      id: _int(json['id']),
      bookingNo: (json['bookingNo'] ?? json['booking_no'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      totalAmount: _double(json['totalAmount'] ?? json['total_amount']),
    );
  }

  static int _int(Object? v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static double _double(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }
}
