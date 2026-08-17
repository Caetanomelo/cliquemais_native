import '../../core/services/remote_content_service.dart';

/// Base for repositories that load their content from [RemoteContentService]
/// — every content repository (curriculum, unit data, AI tutor content)
/// takes the same constructor-injectable service (real by default, a fake
/// in tests) and holds onto it the same way.
abstract class JsonRepository {
  final RemoteContentService content;
  JsonRepository({RemoteContentService? content}) : content = content ?? RemoteContentService();
}
