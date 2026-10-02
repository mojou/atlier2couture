import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../core/format.dart';
import '../core/session.dart';
import '../core/supa.dart';
import '../core/widgets.dart';

/// Fil de discussion : messages en temps réel, envoi, suppression de ses messages.
class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key, required this.conversationId, required this.titre, this.sousTitre});

  final String conversationId;
  final String titre;
  final String? sousTitre;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _messages = <Map<String, dynamic>>[];
  final _saisie = TextEditingController();
  final _defilement = ScrollController();
  RealtimeChannel? _canal;
  Timer? _lecture;
  bool _chargement = true;
  bool _envoi = false;
  Object? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
    _ecouter();
  }

  @override
  void dispose() {
    _lecture?.cancel();
    if (_canal != null) supa.removeChannel(_canal!);
    _saisie.dispose();
    _defilement.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    try {
      final rows = await supa
          .from('messages')
          .select()
          .eq('conversation_id', widget.conversationId)
          .order('created_at', ascending: false)
          .limit(200);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(rows);
        _chargement = false;
      });
      _marquerLu();
    } catch (e) {
      if (mounted) setState(() => _erreur = e);
    }
  }

  void _ecouter() {
    _canal = supa
        .channel('conversation-${widget.conversationId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: widget.conversationId,
          ),
          callback: (p) {
            final m = p.newRecord;
            if (!mounted || _messages.any((x) => x['id'] == m['id'])) return;
            setState(() => _messages.insert(0, m));
            _marquerLu();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'messages',
          callback: (p) {
            final id = p.oldRecord['id'];
            if (mounted) setState(() => _messages.removeWhere((x) => x['id'] == id));
          },
        )
        .subscribe();
  }

  /// Regroupe les accusés de lecture (un appel au plus toutes les 2 secondes).
  void _marquerLu() {
    _lecture?.cancel();
    _lecture = Timer(const Duration(seconds: 2), () {
      supa.rpc('marquer_lu', params: {'c': widget.conversationId}).catchError((_) {});
    });
  }

  Future<void> _envoyer() async {
    final texte = _saisie.text.trim();
    if (texte.isEmpty || _envoi) return;
    setState(() => _envoi = true);
    try {
      final m = await supa
          .from('messages')
          .insert({'conversation_id': widget.conversationId, 'contenu': texte})
          .select()
          .single();
      _saisie.clear();
      if (mounted && !_messages.any((x) => x['id'] == m['id'])) {
        setState(() => _messages.insert(0, m));
      }
      if (_defilement.hasClients) {
        _defilement.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  Future<void> _supprimer(Map<String, dynamic> m) async {
    if (!await confirmer(context, 'Supprimer le message', 'Ce message sera supprimé pour tout le monde.',
        ok: 'Supprimer')) {
      return;
    }
    try {
      await supa.from('messages').delete().eq('id', m['id'] as String);
      if (mounted) setState(() => _messages.removeWhere((x) => x['id'] == m['id']));
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    }
  }

  String _jour(DateTime d) {
    final j = DateTime(d.year, d.month, d.day);
    final diff = aujourdhui().difference(j).inDays;
    if (diff == 0) return 'Aujourd\'hui';
    if (diff == 1) return 'Hier';
    return DateFormat('EEEE d MMMM', 'fr_FR').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.titre, overflow: TextOverflow.ellipsis),
          if (widget.sousTitre != null)
            Text(widget.sousTitre!, style: t.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: _erreur != null
              ? Center(child: Text(messageErreur(_erreur!)))
              : _chargement
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? const EtatVide(icone: Icons.forum_outlined, message: 'Aucun message. Écrivez le premier !')
                      : ListView.builder(
                          controller: _defilement,
                          reverse: true,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          itemCount: _messages.length,
                          itemBuilder: (context, i) => _bulle(i),
                        ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(
              color: t.colorScheme.surface,
              border: Border(top: BorderSide(color: t.dividerColor)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: TextField(
                  controller: _saisie,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 4000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Écrire un message…',
                    counterText: '',
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  onSubmitted: (_) => _envoyer(),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                tooltip: 'Envoyer',
                onPressed: _envoi ? null : _envoyer,
                icon: _envoi
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _bulle(int i) {
    final t = Theme.of(context);
    final m = _messages[i];
    final moi = m['auteur_id'] == utilisateurId;
    final date = lireDate(m['created_at']) ?? DateTime.now();
    // La liste est inversée : l'élément suivant (i + 1) est le message précédent.
    final precedent = i + 1 < _messages.length ? _messages[i + 1] : null;
    final datePrecedente = precedent == null ? null : lireDate(precedent['created_at']);
    final nouveauJour = datePrecedente == null ||
        DateTime(date.year, date.month, date.day) != DateTime(datePrecedente.year, datePrecedente.month, datePrecedente.day);
    final memeAuteur = !nouveauJour && precedent?['auteur_id'] == m['auteur_id'];

    final bulle = GestureDetector(
      onLongPress: moi || Session.instance.estGestionnaire ? () => _supprimer(m) : null,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
        margin: EdgeInsets.only(top: memeAuteur ? 2 : 10),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        decoration: BoxDecoration(
          color: moi ? t.colorScheme.primary : t.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(moi ? 16 : 4),
            bottomRight: Radius.circular(moi ? 4 : 16),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          if (!moi && !memeAuteur)
            Text(m['auteur_nom'] as String? ?? '',
                style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.primary, fontWeight: FontWeight.bold)),
          Text(m['contenu'] as String? ?? '',
              style: TextStyle(color: moi ? t.colorScheme.onPrimary : t.colorScheme.onSurface)),
          Align(
            alignment: Alignment.bottomRight,
            child: Text(heure(date),
                style: t.textTheme.labelSmall?.copyWith(
                    color: (moi ? t.colorScheme.onPrimary : t.colorScheme.onSurface).withAlpha(150))),
          ),
        ]),
      ),
    );

    return Column(crossAxisAlignment: moi ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
      if (nouveauJour)
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(_jour(date), style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.outline)),
          ),
        ),
      bulle,
    ]);
  }
}
