/// The categories every new user starts with. Same list as the server's
/// `backend/internal/datasync/defaults.go`: keep the two in step.
///
/// Without an account the phone creates them itself. When that guest data
/// later joins an account (which got the server's copies), categories with
/// the same name and kind are joined into one (see the sign-in merge).
const defaultCategories =
    <({String name, String kind, String icon, String color})>[
      (
        name: 'Food & dining',
        kind: 'expense',
        icon: 'restaurant',
        color: '#E07A5F',
      ),
      (
        name: 'Groceries',
        kind: 'expense',
        icon: 'local_grocery_store',
        color: '#81B29A',
      ),
      (
        name: 'Transport',
        kind: 'expense',
        icon: 'directions_bus',
        color: '#3D5A80',
      ),
      (name: 'Housing', kind: 'expense', icon: 'home', color: '#9C6644'),
      (
        name: 'Bills & utilities',
        kind: 'expense',
        icon: 'receipt_long',
        color: '#5C6B69',
      ),
      (
        name: 'Shopping',
        kind: 'expense',
        icon: 'shopping_bag',
        color: '#C77DFF',
      ),
      (
        name: 'Health',
        kind: 'expense',
        icon: 'medical_services',
        color: '#D62828',
      ),
      (name: 'Entertainment', kind: 'expense', icon: 'movie', color: '#F2A541'),
      (name: 'Education', kind: 'expense', icon: 'school', color: '#4361EE'),
      (name: 'Travel', kind: 'expense', icon: 'flight', color: '#2A9D8F'),
      (name: 'Personal care', kind: 'expense', icon: 'spa', color: '#E5989B'),
      (
        name: 'Gifts & donations',
        kind: 'expense',
        icon: 'card_giftcard',
        color: '#B5838D',
      ),
      (name: 'Other', kind: 'expense', icon: 'more_horiz', color: '#8D99AE'),
      (name: 'Salary', kind: 'income', icon: 'payments', color: '#2F7734'),
      (name: 'Business', kind: 'income', icon: 'storefront', color: '#2C706E'),
      (name: 'Freelance', kind: 'income', icon: 'work', color: '#729D99'),
      (name: 'Gifts', kind: 'income', icon: 'redeem', color: '#B5838D'),
      (name: 'Interest', kind: 'income', icon: 'savings', color: '#3D5A80'),
      (
        name: 'Other income',
        kind: 'income',
        icon: 'attach_money',
        color: '#8D99AE',
      ),
    ];
