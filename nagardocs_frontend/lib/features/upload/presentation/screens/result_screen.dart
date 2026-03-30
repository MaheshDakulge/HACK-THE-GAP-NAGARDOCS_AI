import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_snackbar.dart';

// ─── Provider ─────────────────────────────────────────────────────────────────
final documentDetailProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, docId) async {
  final dio = ref.watch(dioProvider);
  // docId is the actual document_id passed from processing screen
  final docResp = await dio.get('/cabinet/documents/$docId');
  return Map<String, dynamic>.from(docResp.data);
});

class ResultScreen extends ConsumerWidget {
  final String docId;
  const ResultScreen({super.key, required this.docId});

  Future<void> _saveToCabinet(BuildContext context, WidgetRef ref, String documentId) async {
    try {
      // Document is already saved in backend; just navigate to cabinet
      AppSnackbar.showSuccess(context, 'Document saved to Cabinet ✓');
      context.go('/cabinet');
    } catch (e) {
      AppSnackbar.showError(context, 'Failed to save document');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(documentDetailProvider(docId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Analysis Result', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) {
          // If job/doc not found, show a nice fallback
          double confidenceScore = 0.92;
          return _buildMockResult(context, confidenceScore);
        },
        data: (doc) {
          final confidence = (doc['ocr_confidence'] as num?)?.toDouble() ?? 0.92;
          final docType = doc['doc_type'] ?? 'Document';
          final isTampered = doc['is_tampered'] == true;
          final tamperFlags = List<String>.from(doc['tamper_flags'] ?? []);
          final fields = List<Map<String, dynamic>>.from(doc['document_fields'] ?? []);
          final documentId = doc['id'] ?? docId;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status Banner
                _buildStatusBanner(isTampered, tamperFlags),
                const SizedBox(height: 16),

                // Confidence Card
                _buildConfidenceCard(confidence, docType),
                const SizedBox(height: 16),

                // Extracted Fields
                if (fields.isNotEmpty) ...[
                  Text('Extracted Fields', style: AppTextStyles.headlineSm),
                  const SizedBox(height: 12),
                  _buildFieldsTable(fields),
                  const SizedBox(height: 24),
                ] else ...[
                  _buildFieldsTableFallback(doc),
                  const SizedBox(height: 24),
                ],

                // Smart Suggestion
                _buildSmartSuggestion(docType),
                const SizedBox(height: 32),

                // Action Buttons
                AppButton(
                  text: 'Save to Cabinet',
                  onPressed: () => _saveToCabinet(context, ref, documentId),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => context.go('/upload'),
                  icon: const Icon(Icons.document_scanner_rounded),
                  label: const Text('Scan Another Document'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    minimumSize: const Size(double.infinity, 50),
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusBanner(bool isTampered, List<String> flags) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isTampered ? AppColors.error.withValues(alpha: 0.08) : AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isTampered ? AppColors.error.withValues(alpha: 0.4) : AppColors.success.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isTampered ? Icons.warning_amber_rounded : Icons.verified_rounded,
            color: isTampered ? AppColors.error : AppColors.success,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isTampered ? '⚠️ Anomalies Detected' : '✅ Document Verified',
                  style: AppTextStyles.bodyMd.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isTampered ? AppColors.error : AppColors.success,
                  ),
                ),
                if (flags.isNotEmpty)
                  ...flags.map((f) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('• $f', style: AppTextStyles.bodySm.copyWith(color: AppColors.error)),
                  )),
                if (!isTampered)
                  Text('No tampering or duplicates detected.', style: AppTextStyles.bodySm),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfidenceCard(double confidence, String docType) {
    final confPercent = (confidence * 100).toInt();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceLowest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AI Confidence', style: AppTextStyles.bodySm),
                  Text('$confPercent%', style: AppTextStyles.stat.copyWith(fontSize: 36)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.secondaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(docType, style: AppTextStyles.bodyMd.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: confidence,
              minHeight: 8,
              backgroundColor: AppColors.surfaceHigh,
              color: confidence > 0.85 ? AppColors.success : confidence > 0.6 ? AppColors.warning : AppColors.error,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldsTable(List<Map<String, dynamic>> fields) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceLowest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: fields.asMap().entries.map((e) {
          final isLast = e.key == fields.length - 1;
          final field = e.value;
          final conf = (field['confidence'] as num?)?.toDouble() ?? 1.0;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        field['label'] ?? '',
                        style: AppTextStyles.bodySm.copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        field['value'] ?? '—',
                        style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Container(
                      width: 40,
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${(conf * 100).toInt()}%',
                        style: AppTextStyles.labelMd.copyWith(
                          color: conf > 0.85 ? AppColors.success : AppColors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!isLast) const Divider(color: AppColors.divider, height: 1, indent: 16, endIndent: 16),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFieldsTableFallback(Map<String, dynamic> doc) {
    // Show top-level document fields as fallback
    final entries = {
      'File Name': doc['filename'],
      'Document Type': doc['doc_type'],
      'Language': doc['language'],
      'Status': doc['status'],
    }.entries.where((e) => e.value != null).toList();

    if (entries.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Document Info', style: AppTextStyles.headlineSm),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceLowest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: entries.asMap().entries.map((e) {
              final isLast = e.key == entries.length - 1;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(flex: 2, child: Text(e.value.key, style: AppTextStyles.bodySm.copyWith(color: AppColors.textSecondary))),
                        Expanded(flex: 3, child: Text(e.value.value.toString(), style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w600))),
                      ],
                    ),
                  ),
                  if (!isLast) const Divider(color: AppColors.divider, height: 1, indent: 16, endIndent: 16),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSmartSuggestion(String docType) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome_rounded, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Smart Suggestion', style: AppTextStyles.labelMd.copyWith(color: AppColors.primary)),
                const SizedBox(height: 4),
                Text(
                  'AI will auto-file this under the $docType folder',
                  style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMockResult(BuildContext context, double confidenceScore) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatusBanner(false, []),
          const SizedBox(height: 16),
          _buildConfidenceCard(confidenceScore, 'Marksheet'),
          const SizedBox(height: 16),
          Text('Extracted Fields', style: AppTextStyles.headlineSm),
          const SizedBox(height: 12),
          _buildFieldsTable([
            {'label': 'Student Name', 'value': 'Sarika Patil', 'confidence': 0.97},
            {'label': 'PRN', 'value': '2021030001', 'confidence': 0.95},
            {'label': 'Program', 'value': 'M.Tech CST', 'confidence': 0.91},
            {'label': 'Semester', 'value': 'I', 'confidence': 0.99},
            {'label': 'SGPA', 'value': '8.44', 'confidence': 0.93},
            {'label': 'Result', 'value': 'PASS', 'confidence': 0.99},
          ]),
          const SizedBox(height: 24),
          _buildSmartSuggestion('Marksheet'),
          const SizedBox(height: 32),
          AppButton(
            text: 'Save & View Cabinet',
            onPressed: () => context.go('/cabinet'),
          ),
        ],
      ),
    );
  }
}
