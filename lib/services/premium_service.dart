import 'package:flutter/foundation.dart';
import '../models/vpn_models.dart';
import 'api_service.dart';

class PremiumService extends ChangeNotifier {
  static const List<PremiumPlan> defaultPlans = [
    PremiumPlan(id: 'basic_30', name: 'Basic', days: 30, priceUSD: 3.99, priceDisplay: '\$3.99'),
    PremiumPlan(id: 'standard_60', name: 'Standard', days: 60, priceUSD: 7.00, priceDisplay: '\$7.00'),
    PremiumPlan(id: 'premium_90', name: 'Premium', days: 90, priceUSD: 13.00, priceDisplay: '\$13.00'),
  ];

  List<PremiumPlan> _plans = defaultPlans;
  bool _isLoading = false;
  String? _error;

  List<PremiumPlan> get plans => _plans;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> fetchPlans({ApiService? api}) async {
    if (api == null) return;
    try {
      final planData = await api.getPlans();
      if (planData.isNotEmpty) {
        _plans = planData.map((p) => PremiumPlan(
          id: p.id, name: p.name, days: p.days,
          priceUSD: p.price, priceDisplay: p.priceDisplay,
        )).toList();
        notifyListeners();
      }
    } catch (e) {
      // Keep default plans
    }
  }

  // Purchase premium via Paystack only — use PaystackService + PaystackPaymentScreen

  Future<bool> restorePurchases(String accountId, {ApiService? api}) async {
    _isLoading = true;
    notifyListeners();
    try {
      if (api != null) {
        final status = await api.getPremiumStatus();
        if (status.isPremium) {
          _isLoading = false;
          notifyListeners();
          return true;
        }
      }
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
    return false;
  }

  String getPlanDisplay(PremiumPlan plan) {
    final savings = _calculateSavings(plan);
    if (savings > 0) {
      return '${plan.name} — ${plan.priceDisplay} (Save \$${savings.toStringAsFixed(2)})';
    }
    return '${plan.name} — ${plan.priceDisplay}';
  }

  double _calculateSavings(PremiumPlan plan) {
    final monthlyPrice = plans.first.priceUSD;
    final expectedPrice = monthlyPrice * (plan.days / 30);
    return expectedPrice - plan.priceUSD;
  }

  int getBestValuePlanIndex() {
    double bestValue = 0;
    int bestIndex = 0;
    for (int i = 0; i < plans.length; i++) {
      final savings = _calculateSavings(plans[i]);
      if (savings > bestValue) {
        bestValue = savings;
        bestIndex = i;
      }
    }
    return bestIndex;
  }
}
