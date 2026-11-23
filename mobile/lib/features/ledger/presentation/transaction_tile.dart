import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/app_icon.dart';
import '../../../core/database/app_database.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/amount_text.dart';
import '../application/ledger_providers.dart';
import '../data/ledger_store.dart';
import 'ledger_style.dart';

/// One transaction in a list. Expenses show −, income +, transfers no sign
/// (money moved between own accounts is neither earned nor spent).
class TransactionTile extends ConsumerWidget {
  const TransactionTile({super.key, required this.transaction});

  final MoneyTransaction transaction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = transaction;
    final scheme = Theme.of(context).colorScheme;
    final accounts = {
      for (final a in ref.watch(accountsProvider).value ?? const <Account>[])
        a.id: a,
    };
    final category = t.categoryId == null
        ? null
        : ref.watch(categoryIndexProvider).value?[t.categoryId];
    final from = accounts[t.accountId]?.name ?? 'Account';

    final String title;
    final String where;
    final Widget badge;
    final loan = t.kind == TxKind.loanIn || t.kind == TxKind.loanOut;
    if (loan) {
      title = t.kind == TxKind.loanIn ? 'Loan money in' : 'Loan money out';
      where = from;
      badge = IconBadge(
        icon: HugeIcons.strokeRoundedMoneyExchange01,
        color: scheme.secondary,
      );
    } else if (t.kind == TxKind.transfer) {
      title = 'Transfer';
      where = '$from → ${accounts[t.transferAccountId]?.name ?? 'Account'}';
      badge = IconBadge(
        icon: HugeIcons.strokeRoundedArrowDataTransferHorizontal,
        color: scheme.secondary,
      );
    } else {
      title = category?.name ?? 'Uncategorised';
      where = from;
      badge = IconBadge(
        icon: categoryIcon(category?.icon ?? ''),
        color: colorFromHex(category?.color ?? '', scheme.primary),
      );
    }
    final subtitle = t.note.isEmpty ? where : '$where · ${t.note}';

    return ListTile(
      leading: badge,
      title: Text(title),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: TrailingAmount(
        // Loans and transfers are neither earned nor spent: no colour.
        child: loan
            ? Text(
                formatSigned(
                  t.kind == TxKind.loanOut ? -t.amountMinor : t.amountMinor,
                  t.currency,
                ),
                style: Theme.of(context).textTheme.titleMedium,
              )
            : AmountText(
                minor: t.kind == TxKind.expense
                    ? -t.amountMinor
                    : t.amountMinor,
                currency: t.currency,
                signed: t.kind != TxKind.transfer,
                style: Theme.of(context).textTheme.titleMedium,
              ),
      ),
      // Loan movements belong to their due; edit them there.
      onTap: () => context.push(
        loan && t.dueId != null
            ? Routes.due(t.dueId!)
            : Routes.editTransaction(t.id),
      ),
    );
  }
}
