import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/widgets/pulsing_dot.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

// ─── Providers ────────────────────────────────────────────────────────────────
final adminPresenceProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final dio = ref.watch(dioProvider);
  final response = await dio.get('/admin/presence');
  return response.data as List<dynamic>;
});

final adminActivityProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final dio = ref.watch(dioProvider);
  final response = await dio.get('/admin/activity');
  return response.data as List<dynamic>;
});

final adminSecurityProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final dio = ref.watch(dioProvider);
  final response = await dio.get('/admin/security');
  return Map<String, dynamic>.from(response.data);
});

final adminPendingUsersProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final dio = ref.watch(dioProvider);
  final response = await dio.get('/admin/users', queryParameters: {'status': 'pending'});
  return response.data as List<dynamic>;
});

// ─── Main Screen ──────────────────────────────────────────────────────────────
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _doAdminAction(String endpoint, String successMsg) async {
    try {
      final dio = ref.read(dioProvider);
      await dio.post(endpoint);
      if (mounted) AppSnackbar.showSuccess(context, successMsg);
      // Refresh all admin data
      ref.invalidate(adminPresenceProvider);
      ref.invalidate(adminPendingUsersProvider);
    } on DioException catch (e) {
      final data = e.response?.data;
      final msg = (data is Map ? data['detail'] : null) ?? 'Action failed';
      if (mounted) AppSnackbar.showError(context, msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Admin Console', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            Text('NagarDocs AI', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
          ],
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF002952), AppColors.primary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refresh all',
            onPressed: () {
              ref.invalidate(adminPresenceProvider);
              ref.invalidate(adminActivityProvider);
              ref.invalidate(adminSecurityProvider);
              ref.invalidate(adminPendingUsersProvider);
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (val) {
              if (val == 'logout') ref.read(authProvider.notifier).logout();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'logout',
                child: Text('Logout', style: TextStyle(color: AppColors.error)),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.sensors_rounded, size: 18), text: 'Presence'),
            Tab(icon: Icon(Icons.timeline_rounded, size: 18), text: 'Activity'),
            Tab(icon: Icon(Icons.security_rounded, size: 18), text: 'Security'),
            Tab(icon: Icon(Icons.manage_accounts_rounded, size: 18), text: 'Users'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _PresenceTab(onBan: (id) => _doAdminAction('/admin/ban-user/$id', 'User suspended')),
          const _ActivityTab(),
          _SecurityTab(onResolve: (id) => _doAdminAction('/admin/resolve-tamper/$id', 'Tamper flag cleared')),
          _UsersTab(
            onApprove: (id) => _doAdminAction('/admin/approve-user/$id', 'User approved ✓'),
            onBan: (id) => _doAdminAction('/admin/ban-user/$id', 'User suspended'),
            onPromote: (id) => _doAdminAction('/admin/promote-user/$id', 'Promoted to Admin'),
          ),
        ],
      ),
    );
  }
}

// ─── TAB 1: PRESENCE ─────────────────────────────────────────────────────────
class _PresenceTab extends ConsumerWidget {
  final Future<void> Function(String userId) onBan;
  const _PresenceTab({required this.onBan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminPresenceProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) => _ErrorState(message: e.toString(), onRetry: () => ref.invalidate(adminPresenceProvider)),
      data: (users) {
        if (users.isEmpty) return const _EmptyState(message: 'No users in your department yet.');
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(adminPresenceProvider),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: users.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) {
              final user = users[i];
              final status = user['presence_status'] ?? 'offline';
              final color = status == 'online'
                  ? AppColors.success
                  : status == 'away'
                      ? AppColors.warning
                      : AppColors.outlineVariant;

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLowest,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
                ),
                child: Row(
                  children: [
                    PulsingDot(color: color),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user['name'] ?? 'Unknown', style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                            '${user['designation'] ?? 'Officer'}  •  ${status.toUpperCase()}',
                            style: AppTextStyles.labelMd.copyWith(
                              color: color,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'ban') onBan(user['id']);
                      },
                      icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(value: 'ban', child: Text('Suspend User', style: TextStyle(color: AppColors.error))),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ─── TAB 2: ACTIVITY ─────────────────────────────────────────────────────────
class _ActivityTab extends ConsumerWidget {
  const _ActivityTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminActivityProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) => _ErrorState(message: e.toString(), onRetry: () => ref.invalidate(adminActivityProvider)),
      data: (items) {
        if (items.isEmpty) return const _EmptyState(message: 'No activity logged yet.');
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(adminActivityProvider),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(color: AppColors.divider, height: 1),
            itemBuilder: (ctx, i) {
              final item = items[i];
              final userName = item['users']?['name'] ?? 'Unknown';
              final action = item['action'] ?? 'Action';
              final docName = item['documents']?['filename'] ?? '';
              final ts = item['created_at'] ?? '';
              final shortTime = ts.length >= 19 ? ts.substring(11, 19) : ts;

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.secondaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.history_rounded, color: AppColors.primary, size: 20),
                ),
                title: Text('$userName — $action', style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w600)),
                subtitle: docName.isNotEmpty
                    ? Text(docName, style: AppTextStyles.bodySm, maxLines: 1, overflow: TextOverflow.ellipsis)
                    : null,
                trailing: Text(shortTime, style: AppTextStyles.labelMd),
              );
            },
          ),
        );
      },
    );
  }
}

// ─── TAB 3: SECURITY ─────────────────────────────────────────────────────────
class _SecurityTab extends ConsumerWidget {
  final Future<void> Function(String docId) onResolve;
  const _SecurityTab({required this.onResolve});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminSecurityProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) => _ErrorState(message: e.toString(), onRetry: () => ref.invalidate(adminSecurityProvider)),
      data: (data) {
        final summary = data['summary'] as Map<String, dynamic>? ?? {};
        final tampered = List<dynamic>.from(data['tampered_documents'] ?? []);
        final failed = List<dynamic>.from(data['failed_jobs'] ?? []);

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(adminSecurityProvider),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Summary chips
                Row(
                  children: [
                    _AlertChip(label: '${summary['tamper_count'] ?? 0} Tampered', color: AppColors.error),
                    const SizedBox(width: 8),
                    _AlertChip(label: '${summary['failed_count'] ?? 0} Failed Jobs', color: AppColors.warning),
                    const SizedBox(width: 8),
                    _AlertChip(label: '${summary['stale_count'] ?? 0} Stale Accounts', color: AppColors.textSecondary),
                  ],
                ),
                const SizedBox(height: 24),

                if (tampered.isNotEmpty) ...[
                  Text('🚨 Tampered Documents', style: AppTextStyles.h2.copyWith(color: AppColors.error)),
                  const SizedBox(height: 12),
                  ...tampered.map((doc) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: AppColors.error),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(doc['filename'] ?? 'Document', style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w700)),
                              Text('By: ${doc['users']?['name'] ?? 'Unknown'}  •  ${doc['doc_type'] ?? ''}', style: AppTextStyles.bodySm),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => onResolve(doc['id']),
                          style: TextButton.styleFrom(foregroundColor: AppColors.success),
                          child: const Text('✓ Clear'),
                        ),
                      ],
                    ),
                  )),
                  const SizedBox(height: 24),
                ],

                if (failed.isNotEmpty) ...[
                  Text('⚠️ Failed Upload Jobs', style: AppTextStyles.h2.copyWith(color: AppColors.warning)),
                  const SizedBox(height: 12),
                  ...failed.map((job) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: AppColors.warning),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(job['filename'] ?? 'Unknown File', style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(job['error_message'] ?? 'Unknown error', style: AppTextStyles.bodySm, maxLines: 2),
                          ],
                        )),
                      ],
                    ),
                  )),
                ],

                if (tampered.isEmpty && failed.isEmpty)
                  const _EmptyState(message: '✅ No security alerts right now. All clear!'),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── TAB 4: USERS (PENDING APPROVAL) ─────────────────────────────────────────
class _UsersTab extends ConsumerWidget {
  final Future<void> Function(String) onApprove;
  final Future<void> Function(String) onBan;
  final Future<void> Function(String) onPromote;

  const _UsersTab({required this.onApprove, required this.onBan, required this.onPromote});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminPendingUsersProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) => _ErrorState(message: e.toString(), onRetry: () => ref.invalidate(adminPendingUsersProvider)),
      data: (users) {
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(adminPendingUsersProvider),
          child: users.isEmpty
              ? CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverFillRemaining(
                      child: const _EmptyState(message: '✅ No pending approvals right now.'),
                    )
                  ],
                )
              : ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: users.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (ctx, i) {
            final user = users[i];
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceLowest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.outlineVariant),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: AppColors.secondaryContainer,
                        child: Text(
                          (user['name'] ?? 'U')[0].toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 18),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user['name'] ?? 'Unknown', style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w700)),
                            Text(user['email'] ?? '', style: AppTextStyles.bodySm),
                            if (user['designation'] != null)
                              Text(user['designation'], style: AppTextStyles.labelMd),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('PENDING', style: AppTextStyles.labelMd.copyWith(color: AppColors.warning)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(color: AppColors.divider, height: 1),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => onApprove(user['id']),
                          icon: const Icon(Icons.check_circle_outline, size: 16),
                          label: const Text('Approve'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.success,
                            side: const BorderSide(color: AppColors.success),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => onBan(user['id']),
                          icon: const Icon(Icons.block_rounded, size: 16),
                          label: const Text('Reject'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: const BorderSide(color: AppColors.error),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'promote') onPromote(user['id']);
                        },
                        icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(value: 'promote', child: Text('Promote to Admin')),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      );
      },
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────
class _AlertChip extends StatelessWidget {
  final String label;
  final Color color;
  const _AlertChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: AppTextStyles.labelMd.copyWith(color: color)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_rounded, size: 60, color: AppColors.outlineVariant),
            const SizedBox(height: 16),
            Text(message, style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 60, color: AppColors.error),
            const SizedBox(height: 16),
            Text(message, style: AppTextStyles.bodyMd.copyWith(color: AppColors.error), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
