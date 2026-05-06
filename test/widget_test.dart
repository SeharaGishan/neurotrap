import 'package:flutter_test/flutter_test.dart';
import 'package:neurotrap/main.dart';

void main() {
  testWidgets('NeuroTrap smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const NeuroTrapApp());
  });
}
