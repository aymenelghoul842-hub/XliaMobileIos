import 'package:flutter/foundation.dart';
import 'prefs.dart';

/// Current UI language ('fr' / 'en'), persisted in prefs.
class AppLang {
  static final ValueNotifier<String> lang = ValueNotifier<String>('fr');

  static void load() {
    lang.value = Prefs.getString('selectedLanguage', 'fr');
  }

  static Future<void> set(String l) async {
    lang.value = l;
    await Prefs.setString('selectedLanguage', l);
  }
}

/// Translations (ported from the Angular components).
class S {
  static String t(String key) =>
      (_all[AppLang.lang.value] ?? _all['fr']!)[key] ?? _all['fr']![key] ?? key;

  static const Map<String, Map<String, String>> _all = {
    'fr': {
      'welcome': 'Bienvenue à XLiaMobile',
      'welcomeSub': 'Connectez-vous pour explorer',
      'loginTitle': 'Connexion',
      'loginSub': 'Connectez-vous à votre compte',
      'language': 'Langue',
      'identifier': 'Identifiant',
      'identifierPlaceholder': 'Email ou téléphone',
      'password': 'Mot de passe',
      'passwordPlaceholder': 'Entrez votre mot de passe',
      'unit': 'Unité',
      'chooseUnit': 'Choisir une unité',
      'noUnits': "Cet utilisateur n'a pas d'unités",
      'rememberMe': 'Se souvenir de moi',
      'forgotPassword': 'Mot de passe oublié ?',
      'login': 'Se connecter',
      'loggingIn': 'Connexion...',
      'register': 'Inscription',
      'rights': 'Tous les droits sont réservés',
      'comingSoon': 'Fonctionnalité à venir',
      'fillFields': 'Veuillez remplir tous les champs.',
      'serverUnreachable': 'Le serveur est inaccessible. Essayez plus tard.',
      'invalidCredentials': 'Email ou téléphone incorrect.',
      'invalidPassword': 'Mot de passe incorrect.',
      'noHotels': "Cet utilisateur n'a pas des hôtels.",
      'selectHotel': 'Veuillez sélectionner un hôtel.',
      'serverError': 'Erreur de connexion au serveur.',
      'unexpectedError': "Une erreur inattendue s'est produite. Réessayez.",
      'sessionError': "Erreur lors de la récupération de l'ID de session.",
      'success': 'Connexion réussie!',
      'configError':
          "Configuration du serveur manquante. Veuillez configurer l'application.",
      'hotelConfigMissing': "Configuration de l'hôtel non trouvée.",
      'configure': 'Configurer le serveur',
      'settings': 'Paramètres',
      'logout': 'Se Déconnecter',
      'guest': 'Invité',
      'member': 'Membre',
      'homeTitle': 'État Hôtel',
      'dailyMovement': 'Mouvement de la journée',
      'label': 'Libellé',
      'room': 'Chambre',
      'occupancyRate': '% T.O',
      'pax': 'Pax',
      'roomStatus': 'État Chambre',
      'number': 'Nombre',
      'roomCategory': 'Catégorie Chambre',
      'clients': 'Opérations',
      'status': 'État',
      'roomNumber': 'Chb',
      'name': 'Nom',
      'arrival': 'Arr',
      'departure': 'Dep',
      'time': 'Temps',
      'partialError': "Certaines données n'ont pas pu être chargées",
      'noData': 'Aucune donnée',
      'comingSoonPage': 'Cette page sera portée prochainement.',
    },
    'en': {
      'welcome': 'Welcome to XLiaMobile',
      'welcomeSub': 'Log in to explore',
      'loginTitle': 'Login',
      'loginSub': 'Sign in to your account',
      'language': 'Language',
      'identifier': 'Identifier',
      'identifierPlaceholder': 'Email or phone',
      'password': 'Password',
      'passwordPlaceholder': 'Enter your password',
      'unit': 'Unit',
      'chooseUnit': 'Choose a unit',
      'noUnits': 'This user has no units',
      'rememberMe': 'Remember me',
      'forgotPassword': 'Forgot password?',
      'login': 'Login',
      'loggingIn': 'Logging in...',
      'register': 'Register',
      'rights': 'All rights reserved',
      'comingSoon': 'Feature coming soon',
      'fillFields': 'Please fill all fields.',
      'serverUnreachable': 'Server is unreachable. Try again later.',
      'invalidCredentials': 'Incorrect email or phone.',
      'invalidPassword': 'Incorrect password.',
      'noHotels': 'This user has no hotels.',
      'selectHotel': 'Please select a hotel.',
      'serverError': 'Server connection error.',
      'unexpectedError': 'An unexpected error occurred. Try again.',
      'sessionError': 'Error retrieving session ID.',
      'success': 'Login successful!',
      'configError':
          'Server configuration missing. Please configure the application.',
      'hotelConfigMissing': 'Hotel configuration not found.',
      'configure': 'Configure server',
      'settings': 'Settings',
      'logout': 'Log out',
      'guest': 'Guest',
      'member': 'Member',
      'homeTitle': 'Hotel Status',
      'dailyMovement': 'Daily Movement',
      'label': 'Label',
      'room': 'Room',
      'occupancyRate': '% Occupancy Rate',
      'pax': 'Pax',
      'roomStatus': 'Room Status',
      'number': 'Number',
      'roomCategory': 'Room Category',
      'clients': 'Operations',
      'status': 'Status',
      'roomNumber': 'Room No.',
      'name': 'Name',
      'arrival': 'Arrival',
      'departure': 'Departure',
      'time': 'Time',
      'partialError': 'Some data could not be loaded',
      'noData': 'No data',
      'comingSoonPage': 'This page will be ported soon.',
    },
  };
}
