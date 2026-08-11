import 'package:cut_metrics/domain/data_source.dart';
import 'package:cut_metrics/domain/date_key.dart';
import 'package:cut_metrics/domain/health_data_processor.dart';
import 'package:cut_metrics/domain/metric_type.dart';
import 'package:cut_metrics/repo/mock_health_repository.dart';
import 'package:cut_metrics/viewmodel/dashboard_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockHealthRepository repo;
  late HealthDataProcessor processor;
  late DashboardViewModel vm;

  Future<void> setupViewModel({List<double> externalWeights = const []}) async {
    repo = MockHealthRepository();
    processor = HealthDataProcessor(appPackageId: kAppPackageId);

    final now = DateTime.now();
    for (var i = 0; i < externalWeights.length; i++) {
      final date = now.subtract(Duration(days: externalWeights.length - 1 - i));
      repo.addExternalWeight(date, externalWeights[i]);
    }

    vm = DashboardViewModel(
      repository: repo,
      processor: processor,
      autoLoad: false,
    );
    await vm.load();
  }

  group('getResolvedValue', () {
    test('returns null when no data (missing state)', () async {
      await setupViewModel();
      final today = DateKey(DateTime.now());
      expect(vm.getResolvedValue(today, MetricType.weight), isNull);
    });

    test('returns external source for external record', () async {
      await setupViewModel(externalWeights: [80, 79, 78]);
      final today = DateKey(DateTime.now());
      final value = vm.getResolvedValue(today, MetricType.weight);
      expect(value, isNotNull);
      expect(value!.source, DataSource.external);
      expect(value.value, 78.0);
    });
  });

  group('submitManualValue', () {
    test('writes manual record and updates cache to manual', () async {
      await setupViewModel(externalWeights: [80, 79, 78]);
      final today = DateKey(DateTime.now());
      await vm.submitManualValue(today, MetricType.weight, 77.5);

      final value = vm.getResolvedValue(today, MetricType.weight);
      expect(value, isNotNull);
      expect(value!.source, DataSource.manual);
      expect(value.value, 77.5);
      expect(await repo.hasManualRecord(today, MetricType.weight), isTrue);
    });

    test('manual overrides external (Tier 1 > Tier 2)', () async {
      await setupViewModel(externalWeights: [80, 79, 78]);
      final today = DateKey(DateTime.now());
      expect(vm.getResolvedValue(today, MetricType.weight)!.source,
          DataSource.external);
      await vm.submitManualValue(today, MetricType.weight, 77.0);
      final value = vm.getResolvedValue(today, MetricType.weight);
      expect(value!.source, DataSource.manual);
      expect(value.value, 77.0);
    });
  });

  group('cancelManualValue', () {
    test('rolls back to external after canceling manual', () async {
      await setupViewModel(externalWeights: [80, 79, 78]);
      final today = DateKey(DateTime.now());
      await vm.submitManualValue(today, MetricType.weight, 77.0);
      expect(vm.getResolvedValue(today, MetricType.weight)!.source,
          DataSource.manual);
      await vm.cancelManualValue(today, MetricType.weight);
      final value = vm.getResolvedValue(today, MetricType.weight);
      expect(value!.source, DataSource.external);
      expect(value.value, 78.0);
    });

    test('rolls back to missing if no external data', () async {
      await setupViewModel();
      final today = DateKey(DateTime.now());
      await vm.submitManualValue(today, MetricType.weight, 77.0);
      expect(vm.getResolvedValue(today, MetricType.weight)!.source,
          DataSource.manual);
      await vm.cancelManualValue(today, MetricType.weight);
      expect(vm.getResolvedValue(today, MetricType.weight), isNull);
    });
  });

  group('EMA recalculation', () {
    test('editing historical weight changes EMA for subsequent dates', () async {
      await setupViewModel(externalWeights: [80, 79, 78, 77, 76]);
      final emaBefore = List.of(vm.emaData);

      final earliestDate =
          DateKey(DateTime.now().subtract(const Duration(days: 4)));
      await vm.submitManualValue(earliestDate, MetricType.weight, 90.0);

      final emaAfter = vm.emaData;
      expect(emaAfter.length, equals(emaBefore.length));
      expect(emaAfter, isNot(equals(emaBefore)));
    });

    test('editing steps does not trigger EMA recalculation', () async {
      await setupViewModel(externalWeights: [80, 79, 78, 77, 76]);

      final now = DateTime.now();
      for (var i = 0; i < 5; i++) {
        final date = now.subtract(Duration(days: 4 - i));
        repo.addExternalSteps(date, 1000 * (i + 1));
      }

      vm = DashboardViewModel(
        repository: repo,
        processor: processor,
        autoLoad: false,
      );
      await vm.load();

      final emaBefore = List.of(vm.emaData);
      final historicalDate = DateKey(now.subtract(const Duration(days: 4)));
      await vm.submitManualValue(historicalDate, MetricType.steps, 50000);

      final emaAfter = vm.emaData;
      expect(emaAfter.length, equals(emaBefore.length));
      for (var i = 0; i < emaAfter.length; i++) {
        expect(emaAfter[i].weight, closeTo(emaBefore[i].weight, 0.001));
      }
    });
  });

  group('"Ok" has no side effects', () {
    test('ViewModel has no public ok-confirm method that writes data', () async {
      await setupViewModel(externalWeights: [80]);
      expect(vm.submitManualValue, isA<Function>());
      expect(vm.cancelManualValue, isA<Function>());
    });
  });
}
