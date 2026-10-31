import 'package:flutter/material.dart';

import '../app_globals.dart';
import '../companion/companion.dart';

/// PRACTICE ONLY. No real bank, no real money. Teaches two habits:
/// 1) check name and amount before sending, 2) never share the OTP.
class _MockBanner extends StatelessWidget {
  const _MockBanner();
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: Colors.amber.shade200,
        padding: const EdgeInsets.all(10),
        child: const Text('مشق — یہ اصلی بینک نہیں، کوئی پیسے نہیں جائیں گے  •  PRACTICE, no real money',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      );
}

class BankPracticePage extends StatelessWidget {
  const BankPracticePage({super.key});

  Widget _row(String ur, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Expanded(child: Text(ur, style: const TextStyle(fontSize: 19, color: Colors.black54))),
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('بینک کی مشق  •  Banking practice')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 200),
        children: [
          const _MockBanner(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('پیسے بھیجیں (مشق)', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    _row('کس کو', 'علی احمد'),
                    _row('اکاؤنٹ', '•••• 4821'),
                    _row('رقم', 'Rs 5,000'),
                  ]),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
                child: const Text(
                  'بھیجنے سے پہلے: نام صحیح ہے؟ رقم میں صفر زیادہ تو نہیں؟ دو بار پڑھیں۔\nBefore sending: is the name right? Any extra zero? Read twice.',
                  style: TextStyle(fontSize: 18),
                ),
              ),
              const SizedBox(height: 20),
              CompanionTarget(
                id: Targets.bankReview,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(62)),
                  onPressed: () async {
                    await tapTarget(Targets.bankReview);
                    if (context.mounted) Navigator.pushNamed(context, Screens.bankOtp);
                  },
                  icon: const Icon(Icons.fact_check, size: 28),
                  label: const Text('نام اور رقم چیک کر لی  •  I checked', style: TextStyle(fontSize: 21)),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class BankOtpPage extends StatelessWidget {
  const BankOtpPage({super.key});

  Future<void> _share(BuildContext context) async {
    await tapTarget(Targets.shareOtp); // counted as a wrong choice → help rises
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.red.shade50,
        title: const Text('رکیں! یہ دھوکہ تھا', style: TextStyle(fontSize: 24, color: Colors.red)),
        content: const Text(
          'اگر یہ اصلی ہوتا تو آپ کے پیسے چلے جاتے۔ بینک کبھی فون پر کوڈ نہیں مانگتا۔ کوئی بات نہیں، یہ مشق ہے — دوبارہ کوشش کریں۔\n\nIf this were real, your money would be gone. Banks never ask for the code. It is only practice — try again.',
          style: TextStyle(fontSize: 18),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('سمجھ گئی', style: TextStyle(fontSize: 18))),
        ],
      ),
    );
  }

  Future<void> _refuse(BuildContext context) async {
    final nav = Navigator.of(context);
    await tapTarget(Targets.refuseOtp);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('بالکل صحیح! 🎉', style: TextStyle(fontSize: 26)),
        content: const Text(
          'کوڈ صرف آپ کا ہے۔ کوئی بھی مانگے — فون بند کریں اور کارڈ کے پیچھے لکھے نمبر پر خود بینک کو فون کریں۔\n\nThe code is only yours. Hang up and call the bank yourself using the number on your card.',
          style: TextStyle(fontSize: 18),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('ٹھیک ہے', style: TextStyle(fontSize: 18))),
        ],
      ),
    );
    if (nav.mounted) nav.pushNamedAndRemoveUntil('/', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ایک کال آئی ہے  •  Incoming call')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 200),
        children: [
          const _MockBanner(),
          const SizedBox(height: 16),
          const Center(child: Icon(Icons.phone_in_talk, size: 80, color: Colors.deepOrange)),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '"السلام علیکم، میں بینک سے بول رہا ہوں۔ آپ کی رقم روکنی پڑے گی۔ ابھی آپ کے فون پر جو 6 ہندسوں کا کوڈ آیا ہے، وہ مجھے بتائیں۔"',
              style: TextStyle(fontSize: 21, height: 1.6, fontStyle: FontStyle.italic),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('آپ کیا کریں گی؟  •  What will you do?',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              CompanionTarget(
                id: Targets.shareOtp,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(60)),
                  onPressed: () => _share(context),
                  child: const Text('کوڈ بتا دوں  •  Tell the code', style: TextStyle(fontSize: 20)),
                ),
              ),
              const SizedBox(height: 12),
              CompanionTarget(
                id: Targets.refuseOtp,
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60), backgroundColor: Colors.green),
                  onPressed: () => _refuse(context),
                  child: const Text('کوڈ نہیں بتاؤں گی، فون بند  •  Hang up', style: TextStyle(fontSize: 20)),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
