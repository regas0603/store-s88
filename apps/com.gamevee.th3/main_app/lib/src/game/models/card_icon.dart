// Danh mục icon lá bài. Mỗi entry phải có file SVG tương ứng trong
// assets/cards/ — test/card_assets_test.dart canh điều đó.
//
// Nguồn icon: Microsoft Fluent Emoji (Flat) — MIT License.
// Xem docs/THIRD_PARTY_LICENSES.md và docs/ASSETS.md.

import 'dart:math';

/// Chủ đề bộ thẻ. Người chơi chọn được trong Cài đặt.
enum CardCategory { fruit, animal, food, nature, object, sport, vehicle }

/// Một icon mặt trước của lá bài.
///
/// Đây là value object bất biến: hai lá cùng cặp trỏ tới *cùng* một instance
/// const, nhưng luật so khớp vẫn dựa trên [id] cho rõ ràng.
class CardIcon {
  final String id;
  final String labelVi;
  final String labelEn;
  final CardCategory category;

  const CardIcon(this.id, this.labelVi, this.labelEn, this.category);

  String get asset => 'assets/cards/$id.svg';

  String label(String languageCode) => languageCode == 'en' ? labelEn : labelVi;

  @override
  String toString() => 'CardIcon($id)';
}

/// Kho icon tĩnh + tiện ích sinh bộ bài.
class CardIcons {
  CardIcons._();

  static const String cardBack = 'assets/cards/card_back.svg';

  /// 48 icon, đã lọc để không có hai icon nào trùng cả màu lẫn hình khối.
  static const List<CardIcon> all = <CardIcon>[
    CardIcon('apple', 'Quả táo', 'Apple', CardCategory.fruit),
    CardIcon('banana', 'Quả chuối', 'Banana', CardCategory.fruit),
    CardIcon('grapes', 'Chùm nho', 'Grapes', CardCategory.fruit),
    CardIcon('watermelon', 'Dưa hấu', 'Watermelon', CardCategory.fruit),
    CardIcon('strawberry', 'Dâu tây', 'Strawberry', CardCategory.fruit),
    CardIcon('pineapple', 'Quả dứa', 'Pineapple', CardCategory.fruit),
    CardIcon('avocado', 'Quả bơ', 'Avocado', CardCategory.fruit),
    CardIcon('dog', 'Chú chó', 'Dog', CardCategory.animal),
    CardIcon('cat', 'Chú mèo', 'Cat', CardCategory.animal),
    CardIcon('fox', 'Con cáo', 'Fox', CardCategory.animal),
    CardIcon('panda', 'Gấu trúc', 'Panda', CardCategory.animal),
    CardIcon('lion', 'Sư tử', 'Lion', CardCategory.animal),
    CardIcon('frog', 'Chú ếch', 'Frog', CardCategory.animal),
    CardIcon('penguin', 'Chim cánh cụt', 'Penguin', CardCategory.animal),
    CardIcon('octopus', 'Bạch tuộc', 'Octopus', CardCategory.animal),
    CardIcon('butterfly', 'Con bướm', 'Butterfly', CardCategory.animal),
    CardIcon('bee', 'Chú ong', 'Bee', CardCategory.animal),
    CardIcon('cake', 'Bánh sinh nhật', 'Cake', CardCategory.food),
    CardIcon('burger', 'Hamburger', 'Burger', CardCategory.food),
    CardIcon('pizza', 'Pizza', 'Pizza', CardCategory.food),
    CardIcon('ice_cream', 'Kem ly', 'Ice cream', CardCategory.food),
    CardIcon('donut', 'Bánh donut', 'Donut', CardCategory.food),
    CardIcon('lollipop', 'Kẹo mút', 'Lollipop', CardCategory.food),
    CardIcon('sun', 'Mặt trời', 'Sun', CardCategory.nature),
    CardIcon('moon', 'Mặt trăng', 'Moon', CardCategory.nature),
    CardIcon('star', 'Ngôi sao', 'Star', CardCategory.nature),
    CardIcon('rainbow', 'Cầu vồng', 'Rainbow', CardCategory.nature),
    CardIcon('leaf', 'Lá phong', 'Maple leaf', CardCategory.nature),
    CardIcon('clover', 'Cỏ bốn lá', 'Clover', CardCategory.nature),
    CardIcon('blossom', 'Hoa anh đào', 'Blossom', CardCategory.nature),
    CardIcon('rocket', 'Tên lửa', 'Rocket', CardCategory.object),
    CardIcon('anchor', 'Mỏ neo', 'Anchor', CardCategory.object),
    CardIcon('bulb', 'Bóng đèn', 'Light bulb', CardCategory.object),
    CardIcon('key', 'Chìa khoá', 'Key', CardCategory.object),
    CardIcon('umbrella', 'Chiếc ô', 'Umbrella', CardCategory.object),
    CardIcon('crown', 'Vương miện', 'Crown', CardCategory.object),
    CardIcon('gift', 'Hộp quà', 'Gift', CardCategory.object),
    CardIcon('balloon', 'Bóng bay', 'Balloon', CardCategory.object),
    CardIcon('camera', 'Máy ảnh', 'Camera', CardCategory.object),
    CardIcon('soccer', 'Bóng đá', 'Soccer ball', CardCategory.sport),
    CardIcon('basketball', 'Bóng rổ', 'Basketball', CardCategory.sport),
    CardIcon('guitar', 'Đàn guitar', 'Guitar', CardCategory.sport),
    CardIcon('trophy', 'Cúp vô địch', 'Trophy', CardCategory.sport),
    CardIcon('dice', 'Xúc xắc', 'Dice', CardCategory.sport),
    CardIcon('car', 'Ô tô', 'Car', CardCategory.vehicle),
    CardIcon('plane', 'Máy bay', 'Plane', CardCategory.vehicle),
    CardIcon('sailboat', 'Thuyền buồm', 'Sailboat', CardCategory.vehicle),
    CardIcon('bike', 'Xe đạp', 'Bicycle', CardCategory.vehicle),
  ];

  static List<CardIcon> byCategory(CardCategory category) =>
      all.where((icon) => icon.category == category).toList(growable: false);

  /// Số icon khả dụng cho [category] (null = toàn bộ).
  static int availableCount(CardCategory? category) =>
      category == null ? all.length : byCategory(category).length;

  /// Chọn ngẫu nhiên [pairs] icon KHÁC NHAU.
  ///
  /// Nếu [category] không đủ icon cho số cặp yêu cầu, hàm tự động bù thêm từ
  /// các chủ đề khác thay vì ném lỗi — ưu tiên không làm gãy trải nghiệm chơi.
  static List<CardIcon> pick(
    int pairs, {
    CardCategory? category,
    Random? random,
  }) {
    if (pairs <= 0) return const <CardIcon>[];
    final rng = random ?? Random();
    final primary = <CardIcon>[...(category == null ? all : byCategory(category))];
    primary.shuffle(rng);

    if (primary.length >= pairs) {
      return primary.take(pairs).toList(growable: false);
    }

    final chosen = <CardIcon>[...primary];
    final chosenIds = chosen.map((icon) => icon.id).toSet();
    final filler = all.where((icon) => !chosenIds.contains(icon.id)).toList();
    filler.shuffle(rng);
    chosen.addAll(filler.take(pairs - chosen.length));
    return chosen.toList(growable: false);
  }
}
