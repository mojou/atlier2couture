import 'package:atelier_couture/services/assistant_faq.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('trouve la bonne réponse', () {
    expect(repondreFaq('Comment calculer le métrage d\'un kaba ?'), contains('Calculateur de métrage'));
    expect(repondreFaq('Comment créer une commande ?'), contains('Nouvelle commande'));
    expect(repondreFaq('Comment envoyer une facture sur WhatsApp ?'), contains('icône PDF'));
    expect(repondreFaq('Quelle formule choisir ?'), contains('5 000 FCFA'));
    expect(repondreFaq('Mon alarme ne sonne pas'), contains('Sans restriction'));
    expect(repondreFaq('J\'ai oublié mon mot de passe'), contains('Mot de passe oublié'));
  });

  test('répond en anglais', () {
    expect(repondreFaq('How do I add a client?'), startsWith('Add a client'));
  });

  test('question inconnue : oriente vers le support', () {
    expect(repondreFaq('quel temps fait-il ?'), contains('676 14 33 53'));
  });
}
