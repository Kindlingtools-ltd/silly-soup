import 'package:flutter/material.dart';

import '../models/models.dart';
import '../utils/app_theme.dart';
import 'ingredient_card.dart';

/// The shelf of things to choose from.
///
/// Every item on it starts with today's sound — in the core game there is no
/// wrong choice to make, because there is nothing wrong on the shelf.
class PantryShelf extends StatelessWidget {
  const PantryShelf({
    super.key,
    required this.items,
    required this.onItemChosen,
    this.draggable = true,
    this.showLetters = false,
    this.itemSize = SoupMetrics.ingredientSize,
  });
  final List<SoupWord> items;
  final bool draggable;
  final bool showLetters;
  final double itemSize;
  final ValueChanged<SoupWord> onItemChosen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SoupColours.shelf,
        borderRadius: BorderRadius.circular(SoupMetrics.cardRadius),
        border: Border.all(color: SoupColours.shelfDark, width: 3),
      ),
      child: items.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'The shelf is empty — everything is in the soup!',
                style: SoupTypography.subheading(context),
                textAlign: TextAlign.center,
              ),
            )
          : Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                for (final item in items)
                  IngredientCard(
                    key: ValueKey(item.id),
                    word: item,
                    size: itemSize,
                    draggable: draggable,
                    letter: showLetters ? item.emphasisGrapheme : null,
                    onChosen: () => onItemChosen(item),
                  ),
              ],
            ),
    );
  }
}
