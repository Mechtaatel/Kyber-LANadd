import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:kyber_launcher/core/utils/extensions/date_time_extensions.dart';
import 'package:kyber_launcher/features/nexusmods/services/nexusmods_service.dart';
import 'package:kyber_launcher/features/nexusmods/widgets/graphql_provider.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:logging/logging.dart';
import 'package:nexus_bridge/nexus_bridge.dart';
import 'package:nexus_gql/nexus_gql.dart';

enum SortBy {
  endorsements,
  trending,
  downloads,
  //uniqueDownloads,
  published,
  lastUpdated,
}

extension SortByExtension on SortBy {
  String get name {
    switch (this) {
      case .endorsements:
        return 'Endorsements';
      case .trending:
        return 'Trending';
      case .downloads:
        return 'Downloads';
      case .published:
        return 'Published';
      case .lastUpdated:
        return 'Last Updated';
    }
  }

  Input$ModsSort get gqlSort {
    switch (this) {
      case .endorsements:
        return Input$ModsSort(
          endorsements: .new(direction: .DESC),
        );
      case .trending:
        return Input$ModsSort(
          relevance: .new(direction: .DESC),
        );
      case .downloads:
        return Input$ModsSort(
          downloads: .new(direction: .DESC),
        );
      case .published:
        return Input$ModsSort(
          createdAt: .new(direction: .DESC),
        );
      case .lastUpdated:
        return Input$ModsSort(
          updatedAt: .new(direction: .DESC),
        );
    }
  }

  String get value {
    switch (this) {
      case .endorsements:
        return 'OLD_endorsements';
      case .trending:
        return 'two_weeks_ratings';
      case .downloads:
        return 'OLD_downloads';
      case .lastUpdated:
        return 'lastupdate';
      case .published:
        return 'date';
    }
  }
}

class ModBrowserCubit extends Cubit<ModBrowserState> {
  ModBrowserCubit() : super(const ModBrowserInitial()) {
    final lastIndex = Preferences.general.lastSelectedModBrowserCategory;
    final categories = sl<NexusModsService>().nexusBridge.categories;
    final category =
        lastIndex != null && lastIndex >= 0 && lastIndex < categories.length
        ? categories[lastIndex]
        : categories.first;
    currentCategory = category;
    loadPage();
  }

  ModBrowserPage currentPage = .category;
  NexusCategory? currentCategory;
  SortBy currentSortBy = .endorsements;
  int timeFilter = 0;
  int perPage = Preferences.general.modBrowserPerPage;

  Future<void> setPerPage(int value) async {
    Preferences.general.modBrowserPerPage = value;
    perPage = value;
    await loadPage();
  }

  void setTimeFilter(int value) {
    timeFilter = value;
    loadPage();
  }

  void changeSortBy(SortBy sortBy) {
    currentSortBy = sortBy;
    loadPage();
  }

  void changePage(ModBrowserPage page, {NexusCategory? category}) {
    if (category != null) {
      final categories = sl<NexusModsService>().nexusBridge.categories;
      final index = categories.indexWhere((c) => c.id == category.id);

      if (index != -1) {
        Preferences.general.lastSelectedModBrowserCategory = index;
      }
    }

    currentPage = page;
    currentCategory = category;
    emit(state);
    loadPage();
  }

  void nextPage() {
    if (state is ModBrowserLoaded) {
      final state = this.state as ModBrowserLoaded;
      if (state.page < state.totalPages) {
        loadPage(page: state.page + 1);
      }
    }
  }

  void previousPage() {
    if (state is ModBrowserLoaded) {
      final state = this.state as ModBrowserLoaded;
      if (state.page > 1) {
        loadPage(page: state.page - 1);
      }
    }
  }

  List<Input$BaseFilterValue> getTimeFilter() {
    final timeFilter = <Input$BaseFilterValue>[];
    if (this.timeFilter != 0) {
      timeFilter.add(
        Input$BaseFilterValue(
          value: DateTime.now()
              .subtract(Duration(days: this.timeFilter))
              .secondsSinceEpoch
              .toString(),
          op: .GT,
        ),
      );
    }

    return timeFilter;
  }

  Future<void> loadPage({int page = 1, bool force = false}) async {
    if (sl.get<NexusModsService>().apiToken == null) {
      return;
    }

    if (state is ModBrowserLoading && !force) {
      return;
    }

    emit(
      ModBrowserLoading(
        totalPages: state is ModBrowserLoaded
            ? (state as ModBrowserLoaded).totalPages
            : 0,
        page: page,
      ),
    );

    try {
      final result = await nexusGqlClient!.query$modsByCategory(
        .new(
          variables: .new(
            categoryName: currentCategory!.id.isNotEmpty
                ? [currentCategory!.name]
                : null,
            offset: (page - 1) * perPage,
            perPage: perPage,
            sort: currentSortBy.gqlSort,
            timeFilter: getTimeFilter(),
          ),
        ),
      );

      if (result.hasException) {
        throw result.exception!;
      }

      return emit(
        ModBrowserLoaded(
          mods: result.parsedData!.mods.nodes,
          page: page,
          totalPages: (result.parsedData!.mods.totalCount / perPage).ceil(),
        ),
      );
    } on GraphQLError catch (e) {
      return emit(ModBrowserError(error: e.message));
    } on OperationException catch (e) {
      if (e.graphqlErrors.isEmpty) {
        return emit(ModBrowserError(error: e.originalStackTrace.toString()));
      }

      return emit(ModBrowserError(error: e.graphqlErrors.first.message));
    } catch (e, s) {
      Logger.root.severe('Error loading mods', e, s);
      return emit(ModBrowserError(error: e.toString()));
    }
  }
}

enum ModBrowserPage {
  mostPopular,
  mostEndorsed,
  category,
}

abstract class ModBrowserState {
  const ModBrowserState();
}

class ModBrowserInitial extends ModBrowserState {
  const ModBrowserInitial();
}

class ModBrowserLoading extends ModBrowserState {
  const ModBrowserLoading({
    this.page = 1,
    this.totalPages = 1,
  });

  final int page;
  final int totalPages;
}

class ModBrowserLoaded extends ModBrowserState {
  const ModBrowserLoaded({
    required this.mods,
    this.page = 1,
    this.totalPages = 1,
  });

  final List<Query$modsByCategory$mods$nodes> mods;
  final int page;
  final int totalPages;
}

class ModBrowserError extends ModBrowserState {
  const ModBrowserError({this.error = 'An error occurred.'});

  final String error;
}
