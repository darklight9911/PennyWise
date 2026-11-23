import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/finance_colors.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_icon.dart';
import '../../ledger/data/ledger_store.dart';
import '../../ledger/presentation/day_labels.dart';

/// Today's local date, YYYY-MM-DD.
String todayYmd([DateTime? now]) => localDateOf(now ?? DateTime.now());

/// "Due in 3 days", "Due today", "5 days overdue", "No due date",
/// "Settled" or "Forgiven".
String dueWhenLabel(DueProgress p, String today) {
  if (p.forgiven) return 'Forgiven';
  if (p.settled) return 'Settled';
  final d = p.due.dueDate;
  if (d == null) return 'No due date';
  final days = DateTime.parse(d).difference(DateTime.parse(today)).inDays;
  if (days == 0) return 'Due today';
  if (days == 1) return 'Due tomorrow';
  if (days > 1) return 'Due in $days days';
  return days == -1 ? '1 day overdue' : '${-days} days overdue';
}

/// Warning colour for overdue, muted otherwise.
Color dueWhenColor(BuildContext context, DueProgress p, String today) {
  final fin = context.financeColors;
  return switch (p.status(today)) {
    DueStatus.overdue => fin.expense,
    DueStatus.settled => fin.incomeText,
    DueStatus.open =>
      (p.due.dueDate != null &&
              DateTime.parse(p.due.dueDate!)
                      .difference(DateTime.parse(today))
                      .inDays <=
                  3)
          ? fin.warning
          : fin.muted,
  };
}

String dueKindLabel(String kind) => kind == DueKind.loan ? 'Loan' : 'Bill';

AppIconData dueKindIcon(String kind) => kind == DueKind.loan
    ? HugeIcons.strokeRoundedMoneyExchange01
    : HugeIcons.strokeRoundedInvoice01;

/// "Rahim owes you" / "You owe Rahim".
String dueHeadline(Due d) => d.direction == DueDirection.owedToMe
    ? '${d.person} owes you'
    : 'You owe ${d.person}';

/// Words for one linked transaction in a due's history.
String dueEntryLabel(Due d, MoneyTransaction t) {
  final payment = t.kind == duePaymentKind(d.direction, d.kind);
  if (!payment) {
    return d.direction == DueDirection.owedToMe
        ? 'Money lent'
        : 'Money borrowed';
  }
  return d.direction == DueDirection.owedToMe
      ? 'Payment received'
      : 'Payment made';
}

String reminderLabel(int? days) => switch (days) {
  null => 'No reminder',
  0 => 'On the due date',
  1 => '1 day before',
  7 => '1 week before',
  _ => '$days days before',
};

/// Shown in reminders and summaries: "1200.00 USD".
String moneyLabel(int minor, String currency) =>
    '${formatMinor(minor, currency)} $currency';

/// Due date for display: "Mon 1 Dec".
String dueDateLabel(String ymd) => dayLabel(ymd, DateTime.now());
