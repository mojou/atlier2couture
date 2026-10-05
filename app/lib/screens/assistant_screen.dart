import 'package:flutter/material.dart';

import '../core/session.dart';
import '../core/supa.dart';
import '../core/support.dart';
import '../core/widgets.dart';

const _suggestions = [
  'Comment calculer le métrage d\'un kaba ?',
  'Comment créer une commande ?',
  'Comment envoyer une facture sur WhatsApp ?',
  'Quelle formule choisir ?',
  'Mon alarme ne sonne pas',
  'How do I add a client?',
];

/// Assistant : répond aux questions sur l'application (fonction serveur « assistant »).
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _messages = <({String role, String texte})>[];
  final _saisie = TextEditingController();
  final _defilement = ScrollController();
  bool _attente = false;
  int? _restant;

  @override
  void dispose() {
    _saisie.dispose();
    _defilement.dispose();
    super.dispose();
  }

  void _defilerEnBas() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_defilement.hasClients) {
        _defilement.animateTo(_defilement.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _envoyer([String? texte]) async {
    final question = (texte ?? _saisie.text).trim();
    if (question.isEmpty || _attente) return;
    _saisie.clear();
    setState(() {
      _messages.add((role: 'user', texte: question));
      _attente = true;
    });
    _defilerEnBas();
    try {
      final r = await supa.functions.invoke('assistant', body: {
        'atelier_id': Session.instance.aAtelier ? Session.instance.atelierId : null,
        'messages': [for (final m in _messages) {'role': m.role, 'content': m.texte}],
      });
      final data = r.data as Map?;
      setState(() {
        _messages.add((role: 'assistant', texte: (data?['reponse'] as String?) ?? '…'));
        _restant = (data?['restant'] as num?)?.toInt();
      });
    } catch (e) {
      // La question reste affichée ; on retire seulement le dernier envoi pour pouvoir réessayer.
      if (mounted) {
        setState(() {
          _messages.removeLast();
          _saisie.text = question;
        });
        snack(context, messageErreur(e), erreur: true);
      }
    } finally {
      if (mounted) setState(() => _attente = false);
      _defilerEnBas();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          CircleAvatar(radius: 16, child: Icon(Icons.smart_toy_outlined, size: 18)),
          SizedBox(width: 10),
          Text('Assistant'),
        ]),
        actions: [
          IconButton(
            tooltip: 'Écrire au support',
            icon: const Icon(Icons.support_agent),
            onPressed: () => ecrireAuSupport(context),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ListView(
            controller: _defilement,
            padding: const EdgeInsets.all(12),
            children: [
              _bulle(
                'assistant',
                'Bonjour ! Je suis l\'assistant d\'Atelier Couture. Posez-moi vos questions sur l\'application : '
                    'mesures, calcul du métrage, commandes, factures, formules… '
                    '(I also answer in English.)',
              ),
              if (_messages.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final s in _suggestions) ActionChip(label: Text(s), onPressed: () => _envoyer(s)),
                  ]),
                ),
              for (final m in _messages) _bulle(m.role, m.texte),
              if (_attente)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Row(children: [
                    SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 10),
                    Text('L\'assistant réfléchit…'),
                  ]),
                ),
            ],
          ),
        ),
        if (_restant != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('Questions restantes aujourd\'hui : $_restant', style: t.textTheme.labelSmall),
          ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: t.dividerColor))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: TextField(
                  controller: _saisie,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 2000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Votre question…',
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
                onPressed: _attente ? null : _envoyer,
                icon: const Icon(Icons.send),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _bulle(String role, String texte) {
    final t = Theme.of(context);
    final moi = role == 'user';
    return Align(
      alignment: moi ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .82),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: moi ? t.colorScheme.primary : t.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(moi ? 18 : 4),
            bottomRight: Radius.circular(moi ? 4 : 18),
          ),
        ),
        child: SelectableText(texte, style: TextStyle(color: moi ? t.colorScheme.onPrimary : t.colorScheme.onSurface)),
      ),
    );
  }
}
