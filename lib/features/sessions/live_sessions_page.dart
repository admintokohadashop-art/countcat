import 'package:flutter/material.dart';

import '../../data/database/app_database.dart';
import '../../data/models/live_session.dart';
import '../../data/repositories/live_session_repository.dart';

class LiveSessionsPage extends StatefulWidget {
  const LiveSessionsPage({super.key, this.repository});

  final LiveSessionRepository? repository;

  @override
  State<LiveSessionsPage> createState() => _LiveSessionsPageState();
}

class _LiveSessionsPageState extends State<LiveSessionsPage> {
  final _name = TextEditingController();
  final _search = TextEditingController();
  late final LiveSessionRepository _repository;
  List<LiveSession> _sessions = [];
  int? _selectedId;
  DateTime? _startedAt;
  var _loading = true;
  var _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? LiveSessionRepository(AppDatabase.instance);
    _load();
  }

  Future<void> _load() async {
    final sessions = await _repository.listSessions();
    var selected = await _repository.getSelectedSessionId();
    if (selected == null && sessions.isNotEmpty) {
      selected = sessions.first.id;
      await _repository.setSelectedSessionId(selected);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _sessions = sessions;
      _selectedId = selected;
      _loading = false;
    });
  }

  List<LiveSession> get _visibleSessions {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) {
      return _sessions;
    }
    return _sessions.where((s) => s.name.toLowerCase().contains(q)).toList();
  }

  Future<void> _create() async {
    final text = _name.text.trim();
    if (text.isEmpty || _startedAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama Session dan Waktu Mulai wajib diisi.')),
      );
      return;
    }
    try {
      final session = await _repository.createSession(name: text, startedAt: _startedAt);
      if (!mounted) {
        return;
      }
      _name.clear();
      setState(() => _startedAt = null);
      await _load();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${session.name} dipilih.')),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal membuat session.')),
      );
    }
  }

  Future<void> _pickStartedAt() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: _startedAt ?? DateTime.now(),
    );
    if (date == null || !mounted) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startedAt ?? DateTime.now()),
    );
    if (time == null || !mounted) {
      return;
    }
    setState(() => _startedAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _select(int id) async {
    await _repository.setSelectedSessionId(id);
    if (!mounted) {
      return;
    }
    setState(() => _selectedId = id);
  }

  Future<void> _edit(LiveSession session) async {
    final nameController = TextEditingController(text: session.name);
    DateTime? startedAt = session.startedAt?.toLocal();
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Session'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nama Session')),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Waktu Mulai'),
              subtitle: Text(startedAt?.toString() ?? 'Belum dipilih'),
              trailing: OutlinedButton(
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                    initialDate: startedAt ?? DateTime.now(),
                  );
                  if (date == null) {
                    return;
                  }
                  if (!context.mounted) {
                    return;
                  }
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(startedAt ?? DateTime.now()),
                  );
                  if (time == null) {
                    return;
                  }
                  if (!context.mounted) {
                    return;
                  }
                  setDialogState(() {
                    startedAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                  });
                },
                child: const Text('PILIH'),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('BATAL')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('SIMPAN')),
          ],
        ),
      ),
    );
    if (save != true) {
      return;
    }
    final trimmed = nameController.text.trim();
    // Copy to a final local so Dart can promote the type. `startedAt` is
    // captured and reassigned by the StatefulBuilder closure, so the compiler
    // cannot promote the captured variable to non-null after a null check.
    final concreteStartedAt = startedAt;
    if (trimmed.isEmpty || concreteStartedAt == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama Session dan Waktu Mulai wajib diisi.')),
      );
      return;
    }
    try {
      await _repository.updateSession(id: session.id!, name: trimmed, startedAt: concreteStartedAt);
      await _load();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session diperbarui.')));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal memperbarui session.')));
    }
  }

  Future<void> _delete(LiveSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus Session?'),
        content: Text('Session "${session.name}" akan dihapus. Session yang masih dipakai oleh order tidak dapat dihapus.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('BATAL')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('HAPUS')),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await _repository.deleteSession(session.id!);
      await _load();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session dihapus.')));
    } on SessionInUseException catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Session tidak dapat dihapus karena masih digunakan oleh ${e.linkedOrderCount} pesanan.'),
      ));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal menghapus session.')));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final visible = _visibleSessions;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Live Sessions', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nama Session', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Waktu Mulai'),
            subtitle: Text(_startedAt?.toLocal().toString() ?? 'Belum dipilih'),
            trailing: OutlinedButton(onPressed: _pickStartedAt, child: const Text('PILIH')),
          ),
          Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: _create, child: const Text('BUAT'))),
          const SizedBox(height: 16),
          TextField(
            controller: _search,
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: const InputDecoration(
              labelText: 'Cari Session',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: visible.isEmpty
                ? const Center(child: Text('Belum ada Live Session.'))
                : Scrollbar(
                    thumbVisibility: true,
                    interactive: true,
                    child: RadioGroup<int>(
                      groupValue: _selectedId,
                      onChanged: (value) {
                        if (value != null) {
                          _select(value);
                        }
                      },
                      child: ListView.builder(
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final session = visible[index];
                          return RadioListTile<int>(
                            value: session.id!,
                            title: Text(session.name),
                            subtitle: Text(session.startedAt?.toLocal().toString() ?? 'Waktu mulai belum diatur'),
                            secondary: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  tooltip: 'Edit Session',
                                  onPressed: () => _edit(session),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip: 'Hapus Session',
                                  onPressed: () => _delete(session),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}