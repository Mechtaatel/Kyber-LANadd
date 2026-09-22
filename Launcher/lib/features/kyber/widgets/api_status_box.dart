import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/features/kyber/providers/kyber_api_status_cubit.dart';
import 'package:kyber_launcher/features/lightswitch/models/status.dart';
import 'package:kyber_launcher/features/navigation_bar/widgets/action_bar.dart';
import 'package:kyber_launcher/features/navigation_bar/widgets/title_bar.dart'
    as kl;
import 'package:kyber_launcher/gen/fonts.gen.dart';
import 'package:kyber_launcher/shared/ui/utils/background_blur.dart';

class ApiStatusBox extends StatefulWidget {
  const ApiStatusBox({super.key});

  @override
  State<ApiStatusBox> createState() => _ApiStatusBoxState();
}

class _ApiStatusBoxState extends State<ApiStatusBox> {
  Timer? _timer;
  String? text;

  @override
  void initState() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final cubit = context.read<LightswitchCubit>();
      final nextRefresh = cubit.nextRefresh;
      if (nextRefresh != null) {
        final diff = nextRefresh.difference(DateTime.now());
        if (diff.inSeconds > 0) {
          setState(() {
            text =
                'Next refresh in ${diff.inSeconds} ${diff.inSeconds == 1 ? 'second' : 'seconds'}';
          });
        } else {
          setState(() {
            text = 'Refreshing...';
          });
        }
      }
    });
    super.initState();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NavigationView(
      key: const Key('navigation_view'),
      titleBar: const SizedBox(
        height: 34,
        child: Row(
          children: [
            Expanded(
              child: Padding(padding: .only(left: 16), child: kl.TitleBar()),
            ),
            Expanded(child: ActionBar()),
          ],
        ),
      ),
      content: ScaffoldPage(
        content: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 700,
              minWidth: 700,
              minHeight: 100,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(kDefaultInnerBorderRadius),
              child: BackgroundBlur(
                child: Container(
                  width: 700,
                  decoration: BoxDecoration(
                    border: kDefaultAllBorder,
                    borderRadius: BorderRadius.circular(
                      kDefaultInnerBorderRadius,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ERROR',
                        style: FluentTheme.of(context).typography.subtitle
                            ?.copyWith(
                              fontFamily: FontFamily.battlefrontUI,
                              fontSize: 26,
                              color: Colors.red,
                              shadows: [
                                Shadow(
                                  color: Colors.red.withOpacity(0.95),
                                  offset: const Offset(0, 1),
                                  blurRadius: 20,
                                ),
                              ],
                            ),
                      ),
                      BlocBuilder<LightswitchCubit, LightswitchStatus>(
                        builder: (context, state) {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 10),
                              Flexible(
                                child: Text(
                                  state.message ?? 'KYBER is currently down for maintenance.',
                                  style: const TextStyle(
                                    fontFamily: FontFamily.battlefrontUI,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                text ?? 'Next refresh in 0 seconds',
                                style: const TextStyle(
                                  fontFamily: FontFamily.battlefrontUI,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Button(
                        child: const Text('Continue in LAN mode'),
                        onPressed: () =>
                            context.read<LightswitchCubit>().enableLanMode(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
