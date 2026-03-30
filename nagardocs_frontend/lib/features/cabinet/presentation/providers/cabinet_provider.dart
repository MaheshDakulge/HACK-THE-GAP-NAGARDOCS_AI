import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/dio_client.dart';

class CabinetFolder {
  final String id;
  final String name;
  final int documentCount;

  CabinetFolder({required this.id, required this.name, required this.documentCount});

  factory CabinetFolder.fromJson(Map<String, dynamic> json) {
    int docCount = 0;

    // Synthetic "My Uploads" folder sends document_count as plain int
    if (json['document_count'] is int) {
      docCount = json['document_count'] as int;
    // Real folders from Supabase join: documents(count) → [{count: N}]
    } else if (json['documents'] is List) {
      final docs = json['documents'] as List;
      if (docs.isNotEmpty) {
        docCount = (docs[0]['count'] as num?)?.toInt() ?? 0;
      }
    }

    return CabinetFolder(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown',
      documentCount: docCount,
    );
  }
}

final cabinetListProvider = NotifierProvider<CabinetListNotifier, AsyncValue<List<CabinetFolder>>>(CabinetListNotifier.new);

class CabinetListNotifier extends Notifier<AsyncValue<List<CabinetFolder>>> {
  @override
  AsyncValue<List<CabinetFolder>> build() {
    fetchFolders();
    return const AsyncValue.loading();
  }

  Future<void> fetchFolders() async {
    state = const AsyncValue.loading();
    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get('/cabinet/folders');
      final list = (response.data as List).map((e) => CabinetFolder.fromJson(e)).toList();
      state = AsyncValue.data(list);
    } catch (e) {
      // Re-throw or capture actual error
      state = AsyncValue.error(e, StackTrace.current);
    }
  }
}
