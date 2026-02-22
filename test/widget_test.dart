// Basic test for harupan2
import 'package:flutter_test/flutter_test.dart';
import 'package:harupan2/constants/app_constants.dart';

void main() {
  test('Labels and scores have matching lengths', () {
    expect(AppConstants.labels.length, AppConstants.scores.length);
    expect(AppConstants.labels.length, AppConstants.labelColors.length);
  });

  test('All scores are positive', () {
    for (final score in AppConstants.scores) {
      expect(score, greaterThan(0));
    }
  });

  test('Confidence threshold is within valid range', () {
    expect(AppConstants.confidenceThreshold, greaterThan(0));
    expect(AppConstants.confidenceThreshold, lessThanOrEqualTo(1));
  });

  test('IoU threshold is within valid range', () {
    expect(AppConstants.iouThreshold, greaterThan(0));
    expect(AppConstants.iouThreshold, lessThanOrEqualTo(1));
  });
}
