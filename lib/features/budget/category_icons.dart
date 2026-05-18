import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

// ---------------------------------------------------------------------------
// Keyword → icon suggestion
// ---------------------------------------------------------------------------

/// Returns a Material Symbols icon codepoint inferred from [name], or null.
int? suggestCategoryIcon(String name) {
  final lower = name.toLowerCase();
  for (final (keywords, icon) in _kKeywordMap) {
    if (keywords.any((kw) => lower.contains(kw))) return icon.codePoint;
  }
  return null;
}

final _kKeywordMap = <(List<String>, IconData)>[
  // Food & Drink
  (['grocery', 'groceries', 'supermarket', 'produce', 'vegetable', 'market'], Symbols.local_grocery_store),
  (['restaurant', 'dining', 'dine', 'eatery', 'eat out'],                     Symbols.restaurant),
  (['coffee', 'cafe', 'cafeteria', 'starbucks', 'latte', 'tea shop'],          Symbols.local_cafe),
  (['fastfood', 'fast food', 'pizza', 'burger', 'kfc', 'mcdonald'],            Symbols.fastfood),
  (['bar', 'pub', 'beer', 'alcohol', 'cocktail', 'drinks'],                   Symbols.local_bar),
  (['wine', 'winery', 'vineyard', 'liquor', 'whiskey'],                       Symbols.wine_bar),
  (['bakery', 'bread', 'pastry', 'cake', 'dessert', 'sweet', 'biscuit'],      Symbols.bakery_dining),
  (['ramen', 'noodle', 'sushi', 'asian', 'chinese', 'japanese', 'thai', 'korean', 'indian'], Symbols.ramen_dining),
  (['bbq', 'grill', 'barbecue', 'outdoor dining'],                            Symbols.outdoor_grill),
  (['takeout', 'takeaway', 'delivery', 'zomato', 'swiggy', 'doordash', 'grab food'], Symbols.takeout_dining),
  (['ice cream', 'icecream', 'gelato', 'frozen yogurt'],                      Symbols.icecream),
  (['meal prep', 'set meal', 'tiffin', 'lunchbox'],                           Symbols.set_meal),
  // Transport
  (['petrol', 'fuel', 'gas station', 'diesel', 'filling station'],            Symbols.local_gas_station),
  (['car wash', 'car service', 'auto repair', 'mechanic', 'tyre', 'tire', 'parking', 'toll'], Symbols.directions_car),
  (['uber', 'lyft', 'taxi', 'cab', 'ride share', 'ola', 'grab'],             Symbols.local_taxi),
  (['flight', 'airline', 'airfare', 'airport', 'plane'],                     Symbols.flight),
  (['hotel', 'airbnb', 'resort', 'accommodation', 'motel', 'hostel'],        Symbols.hotel),
  (['travel', 'trip', 'vacation', 'holiday', 'tour', 'luggage'],             Symbols.luggage),
  (['train', 'metro', 'subway', 'mrt', 'lrt'],                              Symbols.train),
  (['bus', 'transit', 'commute', 'public transport'],                        Symbols.directions_bus),
  (['bike', 'bicycle', 'cycling'],                                           Symbols.directions_bike),
  (['motorcycle', 'scooter', 'moped', 'two wheeler'],                        Symbols.two_wheeler),
  // Home & Utilities
  (['rent', 'rental', 'mortgage', 'housing', 'apartment', 'flat', 'home loan', 'lease'], Symbols.home),
  (['electric', 'electricity', 'power bill', 'energy', 'utility'],           Symbols.bolt),
  (['water bill', 'water', 'sewage'],                                        Symbols.water_drop),
  (['internet', 'wifi', 'broadband', 'fibre', 'fiber', 'isp'],              Symbols.wifi),
  (['phone', 'mobile', 'cell', 'telecom', 'wireless', 'sim', 'recharge'],   Symbols.phone_android),
  (['cleaning', 'housekeeping', 'maid', 'cleaner'],                         Symbols.cleaning_services),
  (['repair', 'maintenance', 'handyman', 'plumber', 'electrician', 'fix'],   Symbols.handyman),
  (['renovation', 'remodel', 'build', 'construction'],                       Symbols.construction),
  (['garden', 'lawn', 'landscaping', 'grass', 'plants', 'nursery'],         Symbols.grass),
  (['furniture', 'couch', 'sofa', 'home decor', 'ikea', 'bedding'],         Symbols.weekend),
  // Health & Wellness
  (['medical', 'doctor', 'hospital', 'clinic', 'health', 'specialist'],     Symbols.medical_services),
  (['pharmacy', 'chemist', 'medicine', 'drug', 'prescription', 'vitamin', 'supplement'], Symbols.local_pharmacy),
  (['gym', 'fitness', 'workout', 'exercise', 'swim', 'crossfit', 'lifting'], Symbols.fitness_center),
  (['insurance', 'insur', 'policy', 'premium', 'health cover', 'coverage'], Symbols.health_and_safety),
  (['yoga', 'pilates', 'meditation', 'mindfulness', 'wellness'],             Symbols.self_improvement),
  (['spa', 'massage', 'sauna', 'relaxation'],                               Symbols.spa),
  (['therapy', 'therapist', 'psychiatrist', 'mental health', 'counseling'], Symbols.psychology),
  (['dental', 'dentist', 'orthodontist', 'teeth'],                          Symbols.medical_services),
  (['vision', 'optometrist', 'eye', 'glasses', 'contact lens'],             Symbols.visibility),
  // Education
  (['school', 'college', 'university', 'tuition', 'course', 'class', 'training', 'degree'], Symbols.school),
  (['book', 'reading', 'library', 'kindle', 'magazine'],                    Symbols.menu_book),
  (['laptop', 'computer', 'tech', 'software', 'hardware', 'gadget'],        Symbols.laptop),
  (['science', 'research', 'lab'],                                          Symbols.science),
  (['art', 'drawing', 'painting', 'craft', 'design'],                       Symbols.draw),
  // Entertainment
  (['movie', 'cinema', 'theatre', 'film', 'netflix', 'disney', 'streaming', 'entertainment'], Symbols.movie),
  (['music', 'spotify', 'concert', 'festival', 'apple music'],              Symbols.music_note),
  (['gaming', 'game', 'playstation', 'xbox', 'nintendo', 'esports', 'videogame'], Symbols.sports_esports),
  // Specific sports (before generic fallback so more specific keywords win)
  (['martial art', 'judo', 'bjj', 'taekwondo', 'karate', 'kung fu', 'mma', 'boxing', 'wrestling', 'jiu-jitsu', 'jiujitsu'], Symbols.sports_martial_arts),
  (['tennis', 'badminton', 'squash', 'racquet'],                            Symbols.sports_tennis),
  (['volleyball', 'beach volleyball'],                                      Symbols.sports_volleyball),
  (['rugby', 'american football', 'nfl'],                                   Symbols.sports_rugby),
  (['hockey', 'field hockey', 'ice hockey', 'nhl'],                        Symbols.sports_hockey),
  (['handball'],                                                            Symbols.sports_handball),
  (['gymnastics', 'acrobatics', 'tumbling', 'cheerleading'],               Symbols.sports_gymnastics),
  (['surfing', 'kitesurfing', 'windsurfing'],                              Symbols.surfing),
  (['skiing', 'ski', 'alpine', 'cross-country ski'],                       Symbols.downhill_skiing),
  (['snowboard'],                                                           Symbols.snowboarding),
  (['ice skat', 'figure skat', 'roller skat'],                             Symbols.ice_skating),
  (['kayak', 'canoe'],                                                      Symbols.kayaking),
  (['rowing', 'crew', 'sculling'],                                         Symbols.rowing),
  (['skateboard'],                                                          Symbols.skateboarding),
  (['dog walk', 'dog care', 'dog training'],                               Symbols.pets),
  (['sport', 'cricket', 'football', 'soccer', 'golf', 'basketball', 'athletic'], Symbols.sports),
  (['beach', 'pool', 'swimming'],                                           Symbols.beach_access),
  (['hiking', 'camping', 'trekking', 'outdoor', 'adventure'],               Symbols.hiking),
  (['casino', 'gambling', 'lottery', 'betting', 'poker'],                   Symbols.casino),
  (['nightclub', 'club', 'night out', 'party life', 'nightlife'],           Symbols.nightlife),
  // Shopping & Personal Care
  (['clothing', 'clothes', 'fashion', 'apparel', 'shoes', 'outfit', 'wear'], Symbols.shopping_bag),
  (['shopping', 'amazon', 'online order', 'retail', 'store', 'mall'],       Symbols.shopping_cart),
  (['jewel', 'jewelry', 'watch', 'accessories', 'luxury'],                  Symbols.watch),
  (['salon', 'haircut', 'hair', 'beauty', 'nail', 'personal care', 'grooming'], Symbols.face),
  (['barber', 'shaving', 'beard'],                                          Symbols.content_cut),
  (['laundry', 'dry clean', 'washing', 'ironing'],                          Symbols.local_laundry_service),
  // Kids & Pets
  (['child', 'kids', 'baby', 'daycare', 'nursery', 'nanny', 'childcare'],   Symbols.child_care),
  (['pet', 'dog', 'cat', 'vet', 'veterinary', 'animal', 'kennel'],         Symbols.pets),
  // Finance & Work
  (['bank', 'atm', 'bank fee', 'bank charge', 'overdraft'],                Symbols.account_balance),
  (['saving', 'savings', 'emergency fund', 'nest egg', 'rainy day'],        Symbols.savings),
  (['invest', 'stock', 'shares', 'portfolio', 'etf', 'fund', 'crypto', 'bitcoin'], Symbols.trending_up),
  (['tax', 'income tax', 'gst', 'vat', 'levy'],                            Symbols.receipt_long),
  (['subscription', 'membership', 'annual fee', 'monthly fee', 'recurring'], Symbols.subscriptions),
  (['credit card', 'credit', 'visa', 'mastercard', 'amex'],                Symbols.credit_card),
  (['salary', 'income', 'paycheck', 'wage', 'earning'],                    Symbols.attach_money),
  (['work', 'office', 'business', 'professional', 'stationery', 'conference'], Symbols.work_outline),
  // Other
  (['gift', 'present', 'birthday', 'christmas', 'anniversary'],             Symbols.card_giftcard),
  (['charity', 'donation', 'donate', 'nonprofit', 'ngo'],                  Symbols.volunteer_activism),
  (['event', 'party', 'celebration', 'wedding', 'graduation'],              Symbols.celebration),
  (['farm', 'agriculture', 'crop', 'livestock', 'rural'],                   Symbols.agriculture),
];

// ---------------------------------------------------------------------------
// Curated icon palette — shown in the category icon picker
// ---------------------------------------------------------------------------

final kPickableIcons = <(IconData, String)>[
  // Food & Drink
  (Symbols.local_grocery_store,   'Grocery'),
  (Symbols.restaurant,            'Dining'),
  (Symbols.local_cafe,            'Coffee'),
  (Symbols.fastfood,              'Fast Food'),
  (Symbols.local_bar,             'Bar'),
  (Symbols.wine_bar,              'Wine'),
  (Symbols.bakery_dining,         'Bakery'),
  (Symbols.ramen_dining,          'Asian Food'),
  (Symbols.outdoor_grill,         'BBQ'),
  (Symbols.takeout_dining,        'Takeout'),
  (Symbols.icecream,              'Desserts'),
  (Symbols.set_meal,              'Meal Prep'),
  // Transport
  (Symbols.local_gas_station,     'Fuel'),
  (Symbols.directions_car,        'Car'),
  (Symbols.local_taxi,            'Taxi'),
  (Symbols.flight,                'Flight'),
  (Symbols.train,                 'Train'),
  (Symbols.directions_bus,        'Bus'),
  (Symbols.directions_bike,       'Cycling'),
  (Symbols.two_wheeler,           'Motorcycle'),
  (Symbols.luggage,               'Travel'),
  (Symbols.hotel,                 'Hotel'),
  // Home & Utilities
  (Symbols.home,                  'Home'),
  (Symbols.bolt,                  'Electricity'),
  (Symbols.water_drop,            'Water'),
  (Symbols.wifi,                  'Internet'),
  (Symbols.phone_android,         'Phone'),
  (Symbols.cleaning_services,     'Cleaning'),
  (Symbols.handyman,              'Repairs'),
  (Symbols.construction,          'Renovation'),
  (Symbols.grass,                 'Garden'),
  (Symbols.weekend,               'Furniture'),
  // Health & Wellness
  (Symbols.medical_services,      'Medical'),
  (Symbols.local_pharmacy,        'Pharmacy'),
  (Symbols.fitness_center,        'Gym'),
  (Symbols.health_and_safety,     'Insurance'),
  (Symbols.self_improvement,      'Yoga'),
  (Symbols.spa,                   'Spa'),
  (Symbols.psychology,            'Therapy'),
  // Education
  (Symbols.school,                'Education'),
  (Symbols.menu_book,             'Books'),
  (Symbols.laptop,                'Technology'),
  (Symbols.science,               'Science'),
  (Symbols.draw,                  'Art'),
  // Entertainment
  (Symbols.movie,                 'Movies'),
  (Symbols.music_note,            'Music'),
  (Symbols.sports_esports,        'Gaming'),
  (Symbols.theater_comedy,        'Theater'),
  (Symbols.casino,                'Casino'),
  (Symbols.nightlife,             'Nightlife'),
  // Sports & Activities
  (Symbols.sports,                'Sports'),
  (Symbols.sports_soccer,         'Football'),
  (Symbols.sports_cricket,        'Cricket'),
  (Symbols.sports_basketball,     'Basketball'),
  (Symbols.sports_martial_arts,   'Martial Arts'),
  (Symbols.sports_tennis,         'Tennis'),
  (Symbols.sports_volleyball,     'Volleyball'),
  (Symbols.sports_rugby,          'Rugby'),
  (Symbols.sports_hockey,         'Hockey'),
  (Symbols.sports_handball,       'Handball'),
  (Symbols.sports_gymnastics,     'Gymnastics'),
  (Symbols.surfing,               'Surfing'),
  (Symbols.downhill_skiing,       'Skiing'),
  (Symbols.snowboarding,          'Snowboarding'),
  (Symbols.ice_skating,           'Ice Skating'),
  (Symbols.kayaking,              'Kayaking'),
  (Symbols.rowing,                'Rowing'),
  (Symbols.skateboarding,         'Skateboarding'),
  (Symbols.beach_access,          'Beach'),
  (Symbols.hiking,                'Hiking'),
  // Shopping & Personal Care
  (Symbols.shopping_bag,          'Clothing'),
  (Symbols.shopping_cart,         'Shopping'),
  (Symbols.watch,                 'Jewelry'),
  (Symbols.face,                  'Beauty'),
  (Symbols.content_cut,           'Barber'),
  (Symbols.local_laundry_service, 'Laundry'),
  // Kids & Pets
  (Symbols.child_care,            'Children'),
  (Symbols.pets,                  'Pets'),
  (Symbols.nordic_walking,        'Dog Walking'),
  // Finance & Work
  (Symbols.account_balance,       'Banking'),
  (Symbols.savings,               'Savings'),
  (Symbols.trending_up,           'Investments'),
  (Symbols.receipt_long,          'Tax'),
  (Symbols.subscriptions,         'Subscriptions'),
  (Symbols.credit_card,           'Credit Card'),
  (Symbols.attach_money,          'Income'),
  (Symbols.work_outline,          'Work'),
  // Other
  (Symbols.card_giftcard,         'Gifts'),
  (Symbols.volunteer_activism,    'Charity'),
  (Symbols.celebration,           'Events'),
  (Symbols.agriculture,           'Farm'),
];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// New Symbols icons (searched first — covers icons picked after the migration).
const _kAllSymbols = <IconData>[
  Symbols.local_grocery_store,  Symbols.restaurant,         Symbols.local_cafe,
  Symbols.fastfood,             Symbols.local_bar,          Symbols.wine_bar,
  Symbols.bakery_dining,        Symbols.ramen_dining,       Symbols.outdoor_grill,
  Symbols.takeout_dining,       Symbols.icecream,           Symbols.set_meal,
  Symbols.local_gas_station,    Symbols.directions_car,     Symbols.local_taxi,
  Symbols.flight,               Symbols.hotel,              Symbols.luggage,
  Symbols.train,                Symbols.directions_bus,     Symbols.directions_bike,
  Symbols.two_wheeler,          Symbols.home,               Symbols.bolt,
  Symbols.water_drop,           Symbols.wifi,               Symbols.phone_android,
  Symbols.cleaning_services,    Symbols.handyman,           Symbols.construction,
  Symbols.grass,                Symbols.weekend,            Symbols.medical_services,
  Symbols.local_pharmacy,       Symbols.fitness_center,     Symbols.health_and_safety,
  Symbols.self_improvement,     Symbols.spa,                Symbols.psychology,
  Symbols.visibility,           Symbols.school,             Symbols.menu_book,
  Symbols.laptop,               Symbols.science,            Symbols.draw,
  Symbols.movie,                Symbols.music_note,         Symbols.sports_esports,
  Symbols.sports,               Symbols.sports_soccer,      Symbols.sports_cricket,
  Symbols.sports_basketball,    Symbols.sports_martial_arts, Symbols.sports_tennis,
  Symbols.sports_volleyball,    Symbols.sports_rugby,       Symbols.sports_hockey,
  Symbols.sports_handball,      Symbols.sports_gymnastics,  Symbols.surfing,
  Symbols.downhill_skiing,      Symbols.snowboarding,       Symbols.ice_skating,
  Symbols.kayaking,             Symbols.rowing,             Symbols.skateboarding,
  Symbols.theater_comedy,       Symbols.beach_access,       Symbols.hiking,
  Symbols.casino,               Symbols.nightlife,          Symbols.shopping_bag,
  Symbols.shopping_cart,        Symbols.watch,              Symbols.face,
  Symbols.content_cut,          Symbols.local_laundry_service,
  Symbols.child_care,           Symbols.pets,               Symbols.nordic_walking,
  Symbols.account_balance,
  Symbols.savings,              Symbols.trending_up,        Symbols.receipt_long,
  Symbols.subscriptions,        Symbols.credit_card,        Symbols.attach_money,
  Symbols.work_outline,         Symbols.card_giftcard,      Symbols.volunteer_activism,
  Symbols.celebration,          Symbols.agriculture,
];

// Legacy Material Icons — kept so codepoints stored before the migration still render.
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

/// Returns the [IconData] for a stored [codePoint].
/// Searches Material Symbols first (new picks), then legacy Material Icons.
IconData? iconDataFromCodePoint(int codePoint) {
  for (final icon in _kAllSymbols) {
    if (icon.codePoint == codePoint) return icon;
  }
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
