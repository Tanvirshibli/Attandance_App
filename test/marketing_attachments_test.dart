import 'package:cached_network_image/cached_network_image.dart';
import 'package:employee_attendance/config/app_config.dart';
import 'package:employee_attendance/models/marketing_models.dart';
import 'package:employee_attendance/widgets/marketing_photo_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Photos ride along with marketing records (posts, visits, follow-ups) as an
/// `attachments` array, and the list/detail screens render them through the
/// shared photo widgets. These tests pin the record models that only recently
/// learned to hold attachments, the URL the app renders, and that the widgets
/// collapse to nothing for photo-less records.
void main() {
  final base = AppConfig.attendanceApiBaseUrl.trim().replaceAll(
    RegExp(r'/+$'),
    '',
  );

  group('record attachment parsing', () {
    test('Market reads attachments from the index payload', () {
      final market = Market.fromJson(<String, dynamic>{
        'id': 4,
        'name': 'Rahman Market',
        'attachments': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 1,
            'url': 'https://cdn.test/shed.webp',
            'fileType': 'photo',
            'mimeType': 'image/webp',
          },
        ],
      });

      expect(market.attachments, hasLength(1));
      expect(market.attachments.first.displayUrl, 'https://cdn.test/shed.webp');
      expect(market.attachments.first.mimeType, 'image/webp');
    });

    test('Followup reads attachments', () {
      final followup = Followup.fromJson(<String, dynamic>{
        'id': 7,
        'party_id': 3,
        'employee_id': 19,
        'title': 'Check feed stock',
        'attachments': <Map<String, dynamic>>[
          <String, dynamic>{'id': 2, 'path': 'marketing/followup/7/a.webp'},
        ],
      });

      expect(followup.attachments, hasLength(1));
      expect(
        followup.attachments.first.displayUrl,
        '$base/storage/marketing/followup/7/a.webp',
      );
    });

    test('Party keeps reading attachments', () {
      final party = Party.fromJson(<String, dynamic>{
        'id': 1,
        'partyType': 'farm',
        'name': 'Test Farm',
        'attachments': <Map<String, dynamic>>[
          <String, dynamic>{'id': 3, 'path': 'marketing/party/1/b.webp'},
        ],
      });

      expect(party.attachments, hasLength(1));
      expect(
        party.attachments.first.displayUrl,
        '$base/storage/marketing/party/1/b.webp',
      );
    });

    test('records without the key keep an empty list, never null', () {
      final market = Market.fromJson(<String, dynamic>{'id': 1, 'name': 'M'});
      final followup = Followup.fromJson(<String, dynamic>{
        'id': 1,
        'party_id': 1,
        'employee_id': 1,
      });

      expect(market.attachments, isEmpty);
      expect(followup.attachments, isEmpty);
    });
  });

  group('Attachment.displayUrl', () {
    test('absolute urls are used verbatim', () {
      const a = Attachment(id: 1, url: 'https://cdn.test/photo.webp');
      expect(a.displayUrl, 'https://cdn.test/photo.webp');
    });

    test('a relative url is joined against the API base', () {
      const a = Attachment(id: 1, url: '/storage/marketing/party/1/x.webp');
      expect(a.displayUrl, '$base/storage/marketing/party/1/x.webp');
    });

    test('the stored path is the fallback when the url is missing', () {
      const a = Attachment(id: 1, path: 'marketing/visit/2/y.webp');
      expect(a.displayUrl, '$base/storage/marketing/visit/2/y.webp');
    });

    test('neither url nor path renders nothing', () {
      const a = Attachment(id: 1);
      expect(a.displayUrl, isNull);
    });
  });

  group('photo widgets', () {
    test('marketingPhotoUrls drops unusable attachments and keeps order', () {
      const attachments = <Attachment>[
        Attachment(id: 1),
        Attachment(id: 2, url: 'https://cdn.test/one.webp'),
        Attachment(id: 3, url: 'https://cdn.test/two.webp'),
      ];

      expect(
        marketingPhotoUrls(attachments),
        <String>['https://cdn.test/one.webp', 'https://cdn.test/two.webp'],
      );
    });

    testWidgets('MarketingThumb and MarketingPhotoGrid shrink when empty',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                MarketingThumb(attachments: <Attachment>[]),
                MarketingPhotoGrid(attachments: <Attachment>[]),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(tester.getSize(find.byType(MarketingThumb)), Size.zero);
      expect(tester.getSize(find.byType(MarketingPhotoGrid)), Size.zero);
    });
  });
}
