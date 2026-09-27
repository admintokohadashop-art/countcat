import 'package:flutter/material.dart';

import '../../core/currency/rupiah.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/settings_repository.dart';

class SettingsPage extends StatefulWidget { const SettingsPage({super.key}); @override State<SettingsPage> createState() => _SettingsPageState(); }
class _SettingsPageState extends State<SettingsPage> {
  final _controller = TextEditingController();
  final _repository = SettingsRepository(AppDatabase.instance);
  var _loading = true;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { final value = await _repository.getGlobalHpp(); if (!mounted) return; setState(() { _controller.text = value?.toString() ?? ''; _loading = false; }); }
  Future<void> _save() async { final amount = Rupiah.parse(_controller.text); if (amount == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('HPP harus berupa Rupiah valid.'))); return; } try { await _repository.setGlobalHpp(amount); if (!mounted) return; setState(() => _controller.text = amount.toString()); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Global HPP ${Rupiah.format(amount)} disimpan.'))); } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal menyimpan Global HPP.'))); } }
  @override void dispose() { _controller.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(24), child: _loading ? const Center(child: CircularProgressIndicator()) : ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Global HPP', style: Theme.of(context).textTheme.headlineSmall), const SizedBox(height: 8), Text(_controller.text.isEmpty ? 'Belum diatur' : 'Saat ini: ${Rupiah.format(Rupiah.parse(_controller.text) ?? 0)}'), const SizedBox(height: 20), TextField(controller: _controller, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'HPP (Rupiah)', border: OutlineInputBorder())), const SizedBox(height: 16), FilledButton(onPressed: _save, child: const Text('SIMPAN'))])));
}
