import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as mt;
import 'package:intl/intl.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_collection/kyber_collection.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/features/download_manager/providers/download_manager_cubit.dart';
import 'package:kyber_launcher/features/mod_browser/screens/mod_details.dart';
import 'package:kyber_launcher/features/mods/dialogs/move_directory_dialog.dart';
import 'package:kyber_launcher/features/mods/services/mod_service.dart';
import 'package:kyber_launcher/features/nexusmods/widgets/graphql_provider.dart';
import 'package:kyber_launcher/features/settings/dialogs/chromium_download_dialog.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:kyber_launcher/shared/ui/cards/kyber_container.dart';
import 'package:kyber_launcher/shared/ui/dialog/kyber_dialog.dart';
import 'package:kyber_launcher/shared/ui/utils/background_blur.dart';
import 'package:kyber_launcher/shared/ui/utils/button_builder.dart';
import 'package:kyber_launcher/shared/ui/utils/hover_builder.dart';
import 'package:logging/logging.dart';
import 'package:nexus_gql/nexus_gql.dart';

class ModSelector extends StatefulWidget {
  const ModSelector({super.key});

  @override
  State<ModSelector> createState() => _ModSelectorState();
}

class _ModSelectorState extends State<ModSelector> {
  List<Query$modsByUID$legacyMods$nodes> mods = [];
  Set<String> selectedMods = {};
  final controller = TextEditingController(
    text: FileHelper.getModsDirectory().path,
  );
  final downloadIds = <int, int>{};
  Map<int, FeaturedMod> apiMods = <int, FeaturedMod>{};
  final defaultIds = {
    7847: 27561,
    3658: 26898,
    7143: 28103,
    6249: 20723,
    10920: 32387,
    10950: 31629,
  };

  @override
  void initState() {
    Timer.run(() async {
      final config = await sl
          .get<KyberGRPCService>()
          .launcherClient
          .getLauncherConfig(Empty());
      apiMods = {for (final e in config.featuredMods) e.modId: e};
      for (final item in config.featuredMods) {
        downloadIds[item.modId] = item.fileId.toInt();
      }

      for (final item in defaultIds.entries.take(6 - downloadIds.length)) {
        downloadIds[item.key] = item.value;
      }

      try {
        final result = await nexusGqlClient!.query$modsByUID(
          Options$Query$modsByUID(
            variables: Variables$Query$modsByUID(
              ids: downloadIds.keys
                  .map((e) => Input$CompositeIdInput(gameId: 2229, modId: e))
                  .toList(),
            ),
          ),
        );
        final battlefrontPlus = result.parsedData?.legacyMods.nodes
            .firstWhere((element) => element.modId == 7592)
            .copyWith(name: 'Battlefront Plus', fileSize: 4823449);
        final allOther =
            result.parsedData?.legacyMods.nodes
                .where((element) => element.modId != 7592)
                .toList()
              ?..insert(0, battlefrontPlus!);
        setState(() => mods = allOther ?? []);
      } catch (e) {
        Logger.root.severe('Error fetching mods', e);
      }
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: BackgroundBlur(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: decoColor, width: 2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 14,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                height: 105,
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      spacing: 15,
                                      children: [
                                        Text(
                                          'FEATURED MODS',
                                          style: TextStyle(
                                            fontFamily:
                                                FontFamily.battlefrontUI,
                                            fontSize: 28,
                                            color: kActiveColor,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            border: Border(
                                              top: BorderSide(
                                                color: kActiveColor,
                                              ),
                                              bottom: BorderSide(
                                                color: kActiveColor,
                                              ),
                                            ),
                                          ),
                                          child: Text(
                                            'OPTIONAL',
                                            style: TextStyle(
                                              fontFamily:
                                                  FontFamily.battlefrontUI,
                                              color: kActiveColor,
                                              fontSize: 12,
                                              height: 1,
                                            ),
                                            maxLines: 1,
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      'GET A HEAD START - Choose up to 3 mods to begin downloading or CLICK FINISH TO SKIP'
                                          .toUpperCase(),
                                      style: const TextStyle(
                                        fontFamily: FontFamily.battlefrontUI,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 2,
                          height: 110,
                          color: decoColor,
                        ),
                        Expanded(
                          flex: 10,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                height: 105,
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'YOUR SELECTION',
                                      style: TextStyle(
                                        fontFamily: FontFamily.battlefrontUI,
                                        fontSize: 28,
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        RichText(
                                          text: TextSpan(
                                            children: [
                                              TextSpan(
                                                text: 'Selected: '
                                                    .toUpperCase(),
                                                style: const TextStyle(
                                                  fontFamily:
                                                      FontFamily.battlefrontUI,
                                                  fontSize: 17,
                                                  color: kGrayColor,
                                                ),
                                              ),
                                              TextSpan(
                                                text:
                                                    '${selectedMods.length}/3',
                                                style: const TextStyle(
                                                  fontFamily:
                                                      FontFamily.battlefrontUI,
                                                  fontSize: 17,
                                                  color: kWhiteColor,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        RichText(
                                          text: TextSpan(
                                            children: [
                                              TextSpan(
                                                text: 'Size: '.toUpperCase(),
                                                style: const TextStyle(
                                                  fontFamily:
                                                      FontFamily.battlefrontUI,
                                                  fontSize: 17,
                                                  color: kGrayColor,
                                                ),
                                              ),
                                              TextSpan(
                                                text: formatKiloBytes(
                                                  mods
                                                      .where(
                                                        (element) =>
                                                            selectedMods
                                                                .contains(
                                                                  element.uid,
                                                                ),
                                                      )
                                                      .map((e) => e.fileSize)
                                                      .fold<int>(0, (
                                                        previousValue,
                                                        element,
                                                      ) {
                                                        return previousValue +
                                                            (element ?? -1);
                                                      }),
                                                  1,
                                                ),
                                                style: const TextStyle(
                                                  fontFamily:
                                                      FontFamily.battlefrontUI,
                                                  fontSize: 17,
                                                  color: kWhiteColor,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const CardSection(),
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          if (mods.isEmpty) {
                            return const Center(
                              child: ProgressRing(),
                            );
                          }

                          return Center(
                            child: GridView.builder(
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    childAspectRatio: 2,
                                    crossAxisSpacing: 15,
                                    mainAxisSpacing: 15,
                                  ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 120,
                                vertical: 20,
                              ),
                              itemBuilder: (context, index) {
                                final mod = mods[index];
                                return _ModTile(
                                  selected: selectedMods.contains(mod.uid),
                                  onClick: () async {
                                    if (selectedMods.contains(mod.uid)) {
                                      selectedMods.remove(mod.uid);
                                      setState(() => null);
                                    } else if (selectedMods.length < 3) {
                                      selectedMods.add(mod.uid);
                                      setState(() => null);
                                      var downloadUrl =
                                          'https://www.nexusmods.com/starwarsbattlefront22017/mods/${mod.modId}?tab=files&file_id=${downloadIds[mod.modId]}';
                                      if (mod.modId == 7592) {
                                        downloadUrl =
                                            apiMods[mod.modId]!.modInfo;
                                      }

                                      // TODO: update this to new the download architecture

                                      // TODO: fix this
                                      //final download = Download(
                                      //  link: 'https://www.nexusmods.com/starwarsbattlefront22017/mods/${mod.modId}?tab=files&file_id=${downloadIds[mod.modId]}',
                                      //  modName: mod.name,
                                      //  status: DownloadStatus.queued,
                                      //);
                                      //sl.get<DownloadService>().addDownload(download);
                                      //downloads[mod.uid] = download;
                                    }

                                    //if (selectedMods.contains(mod.uid)) {
                                    //  selectedMods.remove(mod.uid);
                                    //  //sl.get<DownloadService>().cancelDownload(downloads[mod.uid]!);
                                    //  downloads.remove(mod.uid);
                                    //} else {
                                    //  if (selectedMods.length < 3) {
                                    //    selectedMods.add(mod.uid);
                                    //  }
                                    //}
                                  },
                                  selectedIndex:
                                      selectedMods.toList().indexOf(mod.uid) +
                                      1,
                                  mod: mod,
                                );
                              },
                              itemCount: mods.length,
                            ),
                          );
                        },
                      ),
                    ),
                    const CardSection(),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          const Text(
                            'INSTALLED MODS DIRECTORY: ',
                            style: TextStyle(
                              fontFamily: FontFamily.battlefrontUI,
                              fontSize: 17,
                              color: kWhiteColor,
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: HoverBuilder(
                              builder: (context, hovered) {
                                return AnimatedContainer(
                                  height: 40,
                                  duration: const Duration(milliseconds: 150),
                                  decoration: BoxDecoration(
                                    color: mt.Colors.black38,
                                    border: Border.all(
                                      color: hovered
                                          ? kActiveColor
                                          : kDefaultBorder.color,
                                      width: kDefaultBorder.width,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      kDefaultInnerBorderRadius,
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Expanded(
                                        child: Container(
                                          alignment: Alignment.center,
                                          color: Colors.black.withOpacity(.4),
                                          child: mt.TextFormField(
                                            controller: controller,
                                            readOnly: true,
                                            style: const mt.TextStyle(
                                              color: kWhiteColor,
                                              fontFamily:
                                                  FontFamily.battlefrontUI,
                                              fontSize: 16,
                                              height: 1,
                                            ),
                                            decoration:
                                                const mt.InputDecoration(
                                                  isDense: true,
                                                  border: mt.InputBorder.none,
                                                  enabledBorder:
                                                      mt.InputBorder.none,
                                                  focusedBorder:
                                                      mt.InputBorder.none,
                                                  contentPadding:
                                                      EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                      ),
                                                  hintStyle: TextStyle(
                                                    color: kInactiveColor,
                                                    fontFamily: FontFamily
                                                        .battlefrontUI,
                                                    fontSize: 16,
                                                    height: 1,
                                                  ),
                                                ),
                                          ),
                                        ),
                                      ),
                                      const ContainerSeparatorH(),
                                      ButtonBuilder(
                                        onClick: () async {
                                          await showKyberDialog(
                                            builder: (_) =>
                                                const MoveModsDirectoryDialog(),
                                            context: context,
                                          );
                                          controller.text =
                                              ModService.getBasePath();
                                        },
                                        builder: (context, hovered) =>
                                            Container(
                                              child: Padding(
                                                padding: const EdgeInsets.all(
                                                  6,
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      FluentIcons.edit,
                                                      color: hovered
                                                          ? kActiveColor
                                                          : Colors.white,
                                                      size: 21,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  int getSizeFromString(String size) {
    final sizeSplit = size.split('');
    final unit = sizeSplit.sublist(sizeSplit.length - 2).join();
    final value = double.parse(
      sizeSplit.sublist(0, sizeSplit.length - 2).join(),
    );
    switch (unit) {
      case 'KB':
        return (value * 1024).toInt();
      case 'MB':
        return (value * 1024 * 1024).toInt();
      case 'GB':
        return (value * 1024 * 1024 * 1024).toInt();
      default:
        return 0;
    }
  }
}

class _ModTile extends StatelessWidget {
  const _ModTile({
    required this.onClick,
    required this.mod,
    required this.selected,
    this.selectedIndex,
  });

  final VoidCallback onClick;
  final Query$modsByUID$legacyMods$nodes mod;
  final bool selected;
  final int? selectedIndex;

  @override
  Widget build(BuildContext context) {
    return ButtonBuilder(
      onClick: onClick,
      builder: (context, hovered) {
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: hovered ? kActiveColor : decoColor,
              width: 2,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ShaderMask(
                    shaderCallback: (rect) {
                      return const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black,
                        ],
                      ).createShader(
                        Rect.fromLTRB(0, 0, rect.width, rect.height),
                      );
                    },
                    blendMode: BlendMode.dstOut,
                    child: Image.network(
                      mod.modId == 7592
                          ? 'https://battlefront.plus/assets/gallery/maincover_v2.webp'
                          : mod.pictureUrl ?? '',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: hovered ? 1 : 0,
                    child: Container(
                      color: Colors.black.withOpacity(.5),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    reverseDuration: const Duration(milliseconds: 150),
                    child: hovered
                        ? Padding(
                            padding: const EdgeInsets.only(
                              left: 14,
                              top: 14,
                              right: 14,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  mod.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 19,
                                    color: kActiveColor,
                                    height: 1,
                                  ),
                                  maxLines: 2,
                                ),
                                const SizedBox(height: 15),
                                Expanded(
                                  child: Text(
                                    mod.summary.trimLeft(),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      letterSpacing: 0.05,
                                      wordSpacing: 0,
                                      fontWeight: FontWeight.w400,
                                      height: 1.1,
                                    ),
                                    overflow: TextOverflow.fade,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Padding(
                            key: UniqueKey(),
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  mod.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 19,
                                    color: Colors.white,
                                    height: 1,
                                  ),
                                  maxLines: 2,
                                ),
                                const SizedBox(height: 5),
                                Row(
                                  children: [
                                    Text(
                                      formatKiloBytes(mod.fileSize ?? -1, 1),
                                      style: const TextStyle(
                                        fontFamily: FontFamily.battlefrontUI,
                                        fontSize: 14,
                                        color: kWhiteColor,
                                        height: 1,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    const Icon(
                                      FluentIcons.download,
                                      size: 16,
                                      color: kWhiteColor,
                                    ),
                                    Text(
                                      NumberFormat(
                                        '#,###',
                                      ).format(mod.downloads),
                                      style: const TextStyle(
                                        fontFamily: FontFamily.battlefrontUI,
                                        fontSize: 14,
                                        color: kWhiteColor,
                                        height: 1,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
                if (selected && !hovered)
                  Positioned(
                    top: 15,
                    left: 15,
                    child: Container(
                      width: 35,
                      height: 35,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        border: Border.all(color: kActiveColor, width: 2),
                        color: Colors.black.withOpacity(.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Center(
                        child: Text(
                          selectedIndex.toString(),
                          style: TextStyle(
                            fontFamily: FontFamily.battlefrontUI,
                            fontSize: 18,
                            height: 1,
                            fontWeight: FontWeight.bold,
                            color: kActiveColor,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
