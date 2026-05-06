import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Keyword → icon suggestion
// ---------------------------------------------------------------------------

/// Returns a Material icon codepoint inferred from [name], or null if unknown.
int? suggestCategoryIcon(String name) {
  final lower = name.toLowerCase();
  for (final (keywords, icon) in _kKeywordMap) {
    if (keywords.any((kw) => lower.contains(kw))) return icon.codePoint;
  }
  return null;
}

final _kKeywordMap = <(List<String>, IconData)>[
  (['petrol', 'fuel', 'gas station', 'filling', 'diesel'],          Icons.local_gas_station),
  (['grocery', 'groceries', 'supermarket', 'produce', 'vegetable'], Icons.local_grocery_store),
  (['coffee', 'cafe', 'cafeteria', 'starbucks', 'tea shop'],        Icons.local_cafe),
  (['restaurant', 'dining', 'dine', 'takeaway', 'takeout', 'pizza',
    'burger', 'sushi', 'lunch', 'dinner', 'breakfast', 'eatery'],   Icons.restaurant),
  (['bar', 'pub', 'beer', 'wine', 'alcohol', 'liquor', 'cocktail'], Icons.local_bar),
  (['car wash', 'car service', 'car maintenance', 'auto repair',
    'mechanic', 'tyre', 'tire', 'parking', 'toll'],                 Icons.directions_car),
  (['uber', 'lyft', 'ola', 'taxi', 'cab', 'ride share'],            Icons.local_taxi),
  (['flight', 'airline', 'airfare', 'airport'],                     Icons.flight),
  (['travel', 'trip', 'vacation', 'holiday', 'hotel', 'airbnb',
    'resort', 'tour'],                                              Icons.luggage),
  (['train', 'metro', 'subway', 'transit', 'bus', 'commute', 'mrt'], Icons.train),
  (['rent', 'rental', 'mortgage', 'housing', 'apartment', 'flat',
    'home loan', 'lease'],                                          Icons.home),
  (['electric', 'electricity', 'power bill', 'energy', 'utility',
    'utilities', 'water bill', 'sewage'],                           Icons.bolt),
  (['internet', 'wifi', 'broadband', 'isp', 'fibre', 'fiber'],      Icons.wifi),
  (['phone', 'mobile', 'cell', 'telecom', 'wireless', 'sim',
    'recharge'],                                                    Icons.phone_android),
  (['medical', 'doctor', 'hospital', 'clinic', 'health', 'dental',
    'dentist', 'vision', 'physio', 'therapist', 'specialist'],      Icons.medical_services),
  (['pharmacy', 'chemist', 'medicine', 'drug', 'prescription',
    'vitamin', 'supplement'],                                       Icons.local_pharmacy),
  (['gym', 'fitness', 'workout', 'yoga', 'pilates', 'exercise',
    'swim', 'crossfit'],                                            Icons.fitness_center),
  (['insurance', 'insur', 'policy', 'premium', 'coverage'],         Icons.health_and_safety),
  (['school', 'college', 'university', 'tuition', 'course', 'class',
    'training', 'certificate', 'degree', 'study'],                  Icons.school),
  (['book', 'reading', 'library', 'kindle', 'magazine'],            Icons.menu_book),
  (['movie', 'cinema', 'theatre', 'theater', 'film', 'netflix',
    'disney', 'hulu', 'prime video', 'streaming', 'entertainment'], Icons.movie),
  (['music', 'spotify', 'apple music', 'concert', 'festival'],      Icons.music_note),
  (['subscription', 'membership', 'annual fee', 'monthly fee',
    'recurring'],                                                   Icons.subscriptions),
  (['clothing', 'clothes', 'fashion', 'apparel', 'shoes', 'wear',
    'outfit', 'dress', 'shirt', 'jeans'],                           Icons.shopping_bag),
  (['shopping', 'amazon', 'online order', 'retail', 'store', 'mall'], Icons.shopping_cart),
  (['child', 'kids', 'baby', 'daycare', 'nursery', 'childcare',
    'nanny'],                                                       Icons.child_care),
  (['pet', 'dog', 'cat', 'vet', 'veterinary', 'animal', 'kennel'],  Icons.pets),
  (['gift', 'present', 'birthday', 'christmas', 'anniversary'],      Icons.card_giftcard),
  (['salon', 'haircut', 'hair', 'beauty', 'spa', 'massage', 'nail',
    'barber', 'personal care', 'grooming'],                         Icons.face),
  (['charity', 'donation', 'donate', 'nonprofit', 'ngo'],           Icons.volunteer_activism),
  (['tax', 'income tax', 'gst', 'vat', 'levy'],                     Icons.receipt_long),
  (['bank fee', 'bank charge', 'account fee', 'overdraft', 'atm'],  Icons.account_balance),
  (['saving', 'savings', 'emergency fund', 'nest egg', 'rainy day'], Icons.savings),
  (['invest', 'stock', 'shares', 'portfolio', 'etf', 'fund',
    'crypto', 'bitcoin'],                                           Icons.trending_up),
  (['work', 'office', 'business', 'professional', 'stationery'],    Icons.work_outline),
  (['sport', 'cricket', 'football', 'soccer', 'tennis', 'golf',
    'basketball', 'badminton', 'gaming'],                           Icons.sports),
  (['food', 'eat', 'snack', 'meal', 'kitchen'],                     Icons.fastfood),
];

// ---------------------------------------------------------------------------
// Curated icon palette for manual picking
// ---------------------------------------------------------------------------

final kPickableIcons = <(IconData, String)>[
  (Icons.local_grocery_store,  'Grocery'),
  (Icons.restaurant,           'Dining'),
  (Icons.local_cafe,           'Coffee'),
  (Icons.fastfood,             'Fast Food'),
  (Icons.local_bar,            'Bar'),
  (Icons.local_gas_station,    'Fuel'),
  (Icons.directions_car,       'Car'),
  (Icons.local_taxi,           'Taxi'),
  (Icons.flight,               'Flight'),
  (Icons.luggage,              'Travel'),
  (Icons.train,                'Transit'),
  (Icons.home,                 'Home'),
  (Icons.bolt,                 'Utilities'),
  (Icons.wifi,                 'Internet'),
  (Icons.phone_android,        'Phone'),
  (Icons.medical_services,     'Medical'),
  (Icons.local_pharmacy,       'Pharmacy'),
  (Icons.fitness_center,       'Gym'),
  (Icons.health_and_safety,    'Insurance'),
  (Icons.school,               'Education'),
  (Icons.menu_book,            'Books'),
  (Icons.movie,                'Movies'),
  (Icons.music_note,           'Music'),
  (Icons.sports,               'Sports'),
  (Icons.subscriptions,        'Subscriptions'),
  (Icons.shopping_bag,         'Clothing'),
  (Icons.shopping_cart,        'Shopping'),
  (Icons.child_care,           'Children'),
  (Icons.pets,                 'Pets'),
  (Icons.card_giftcard,        'Gifts'),
  (Icons.face,                 'Beauty'),
  (Icons.volunteer_activism,   'Charity'),
  (Icons.receipt_long,         'Tax'),
  (Icons.account_balance,      'Bank'),
  (Icons.savings,              'Savings'),
  (Icons.trending_up,          'Invest'),
  (Icons.work_outline,         'Work'),
  (Icons.celebration,          'Events'),
  (Icons.laptop,               'Tech'),
  (Icons.construction,         'Repairs'),
];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// All IconData values this app may store.
/// Keeping an explicit const list lets the tree-shaker know exactly which
/// glyphs to include in the release font — never create IconData dynamically.
const _kAllIcons = <IconData>[
  Icons.local_grocery_store, Icons.restaurant,       Icons.local_cafe,
  Icons.fastfood,            Icons.local_bar,        Icons.local_gas_station,
  Icons.directions_car,      Icons.local_taxi,       Icons.flight,
  Icons.luggage,             Icons.train,            Icons.home,
  Icons.bolt,                Icons.wifi,             Icons.phone_android,
  Icons.medical_services,    Icons.local_pharmacy,   Icons.fitness_center,
  Icons.health_and_safety,   Icons.school,           Icons.menu_book,
  Icons.movie,               Icons.music_note,       Icons.sports,
  Icons.subscriptions,       Icons.shopping_bag,     Icons.shopping_cart,
  Icons.child_care,          Icons.pets,             Icons.card_giftcard,
  Icons.face,                Icons.volunteer_activism, Icons.receipt_long,
  Icons.account_balance,     Icons.savings,          Icons.trending_up,
  Icons.work_outline,        Icons.celebration,      Icons.laptop,
  Icons.construction,
];

/// Returns the [IconData] constant for a stored [codePoint], or null if unknown.
IconData? iconDataFromCodePoint(int codePoint) {
  for (final icon in _kAllIcons) {
    if (icon.codePoint == codePoint) return icon;
  }
  return null;
}

/// Builds an [Icon] from a stored codepoint, or an empty box if not found.
Widget iconFromCodePoint(int codePoint, {double size = 18, Color? color}) {
  final data = iconDataFromCodePoint(codePoint);
  if (data == null) return SizedBox(width: size, height: size);
  return Icon(data, size: size, color: color);
}
