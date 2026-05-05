import 'package:flutter_test/flutter_test.dart';
import 'package:games_tool/widgets/grouped_list.dart';

class _Group {
  _Group(this.id, this.collapsed);
  final String id;
  final bool collapsed;
}

class _Item {
  _Item(this.id, this.groupId);
  final String id;
  String groupId;
}

void main() {
  test('buildRows hides item rows when group is collapsed', () {
    final List<_Group> groups = <_Group>[
      _Group('main', false),
      _Group('other', true),
    ];
    final List<_Item> items = <_Item>[
      _Item('a', 'main'),
      _Item('b', 'other'),
    ];

    final List<GroupedListRow<_Group, _Item>> rows =
        GroupedListAlgorithms.buildRows<_Group, _Item>(
      groups: groups,
      items: items,
      mainGroupId: 'main',
      groupIdOf: (group) => group.id,
      groupCollapsedOf: (group) => group.collapsed,
      itemGroupIdOf: (item) => item.groupId,
    );

    final GroupedListRow<_Group, _Item> visibleRow =
        rows.firstWhere((row) => row.isItem && row.item!.id == 'a');
    final GroupedListRow<_Group, _Item> hiddenRow =
        rows.firstWhere((row) => row.isItem && row.item!.id == 'b');

    expect(visibleRow.hiddenByCollapse, isFalse);
    expect(hiddenRow.hiddenByCollapse, isTrue);
  });

  test('reassignItemsToGroup moves only matching items', () {
    final List<_Item> items = <_Item>[
      _Item('one', 'main'),
      _Item('two', 'legacy'),
      _Item('three', 'legacy'),
      _Item('four', 'other'),
    ];

    final int moved = GroupedListAlgorithms.reassignItemsToGroup<_Item>(
      items: items,
      fromGroupId: 'legacy',
      toGroupId: 'main',
      itemGroupIdOf: (item) => item.groupId,
      setItemGroupId: (item, nextGroupId) {
        item.groupId = nextGroupId;
      },
    );

    expect(moved, 2);
    expect(items.map((item) => item.groupId).toList(), <String>[
      'main',
      'main',
      'main',
      'other',
    ]);
  });
}
