import 'dart:async';
import 'dart:io';

import 'package:better_player/better_player.dart';
import 'package:chatsen/Accounts/AccountsCubit.dart';
import 'package:chatsen/Components/HomeEndDrawer.dart';
import 'package:chatsen/Components/Modal/SetupModal.dart';
import 'package:chatsen/Components/Modal/UpdateModal.dart';
import 'package:chatsen/Mentions/MentionsCubit.dart';
import 'package:chatsen/Settings/Settings.dart';
import 'package:chatsen/Settings/SettingsEvent.dart';
import 'package:chatsen/Settings/SettingsState.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '/Components/ChannelJoinModal.dart';
import '/Components/HomeDrawer.dart';
import '/Components/HomeTab.dart';
import '/Components/Notification.dart';
import '/StreamOverlay/StreamOverlayBloc.dart';
import '/StreamOverlay/StreamOverlayState.dart';
import '/Views/Chat.dart';
import 'package:flutter_chatsen_irc/Twitch.dart' as twitch;
import 'package:hive/hive.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'Account.dart';

/// Our [HomePage]. This will contain access to everything: from Settings via a drawer, access to the different chat channels to everything else related to our application.
class HomePage extends StatefulWidget {
  const HomePage({
    Key? key,
    // @required this.client,
  }) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> implements twitch.Listener {
  twitch.Client client = twitch.Client();
  Future<bool>? updateFuture;

  Future<void> loadChannelHistory() async {
    var channels = await Hive.openBox('Channels');
    await client.joinChannels(List<String>.from(channels.values));
    setState(() {});
  }

  late WebViewController _myController;
  final Completer<WebViewController> _controller =
  Completer<WebViewController>();

  @override
  void initState() {
    Future.delayed(Duration(seconds: 2)).then(
      (t) => BlocProvider.of<AccountsCubit>(context).getActive().then(
            (account) => client.swapCredentials(
              twitch.Credentials(
                clientId: account.clientId,
                id: account.id,
                login: account.login!,
                token: account.token,
              ),
            ),
          ),
    );

    // AccountPresenter.findCurrentAccount().then(
    //   (account) async {
    //     print(account!.login);
    //     client.swapCredentials(
    //       twitch.Credentials(
    //         clientId: account.clientId,
    //         id: account.id,
    //         login: account.login!,
    //         token: account.token,
    //       ),
    //     );
    //   },
    // );

    loadChannelHistory();

    client.listeners.add(this);

    updateFuture = UpdateModal.hasUpdate();

    Timer.periodic(Duration(minutes: 5), (timer) {
      print('Checking for updates...');
      setState(() {
        updateFuture = UpdateModal.hasUpdate();
      });
    });

    SchedulerBinding.instance!.addPostFrameCallback((_) async {
      UpdateModal.searchForUpdate(context);
      var settingsState = BlocProvider.of<Settings>(context).state;
      if (settingsState is SettingsLoaded && settingsState.setupScreen) {
        await SetupModal.show(context);
        BlocProvider.of<Settings>(context).add(SettingsChange(state: settingsState.copyWith(setupScreen: false)));
      }
    });

    super.initState();
    if (Platform.isAndroid) WebView.platform = SurfaceAndroidWebView();
  }

  @override
  void dispose() {
    client.listeners.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: client.channels.length,
        child: BlocBuilder<StreamOverlayBloc, StreamOverlayState>(
          builder: (context, state) {
            var horizontal = MediaQuery.of(context).size.aspectRatio > 1.0;
            // // var videoPlayer = Container(color: Theme.of(context).primaryColor);

            if (state is StreamOverlayOpened && horizontal) {
              SystemChrome.setEnabledSystemUIOverlays([]);
            } else {
              SystemChrome.setEnabledSystemUIOverlays(SystemUiOverlay.values);
            }

            var videoPlayer = state is StreamOverlayOpened
                /*? WebView(
                    initialUrl: 'https://player.twitch.tv/?channel=${state.channelName}&enableExtensions=true&muted=false&parent=pornhub.com',
                    javascriptMode: JavascriptMode.unrestricted,
                    allowsInlineMediaPlayback: true,
                    onWebViewCreated: (WebViewController webViewController) {
                      webViewController.evaluateJavascript(
                          'const script=document.createElement("script");script.type="text/javascript";script.src="https://i.stphn.cc/trihard.js?487216";document.head.appendChild(script);');
                    }
                  )*/
                ? BetterPlayer.network(
                  "https://trihard.stphn.cc/${state.channelName}.m3u8",
                  betterPlayerConfiguration: BetterPlayerConfiguration(
                    aspectRatio: 16 / 9,
                    autoPlay: true
                  ),
                )
                : null;

            var scaffold = Scaffold(
              extendBody: true,
              extendBodyBehindAppBar: true,
              drawer: Builder(
                builder: (context) {
                  var currentChannel = client.channels.isNotEmpty ? client.channels[DefaultTabController.of(context)!.index] : null;
                  return HomeDrawer(
                    client: client,
                    channel: currentChannel,
                  );
                },
              ),
              endDrawer: HomeEndDrawer(),
              bottomNavigationBar: Builder(
                builder: (context) => Material(
                  color: client.channels.isEmpty ? Theme.of(context).colorScheme.surface.withAlpha(196) : Colors.transparent,
                  child: SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (client.channels.isEmpty) Ink(height: 1.0, color: Theme.of(context).dividerColor),
                        SizedBox(
                          height: 32.0,
                          child: Row(
                            children: [
                              Builder(
                                builder: (context) => InkWell(
                                  onTap: () async => Scaffold.of(context).openDrawer(),
                                  child: Container(
                                    height: 32.0,
                                    width: 32.0,
                                    child: Icon(
                                      Icons.menu,
                                      color: Theme.of(context).colorScheme.onSurface.withAlpha(64 * 3),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Material(
                                  color: Colors.transparent,
                                  child: TabBar(
                                    labelPadding: EdgeInsets.only(left: 8.0),
                                    isScrollable: true,
                                    tabs: client.channels
                                        .map(
                                          (channel) => HomeTab(
                                            client: client,
                                            channel: channel,
                                            refresh: () => setState(() {}),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ),
                              ),
                              Tooltip(
                                message: 'Add/join a channel',
                                child: InkWell(
                                  onTap: () async {
                                    await showModalBottomSheet(
                                      context: context,
                                      backgroundColor: Colors.transparent,
                                      builder: (context) => SafeArea(
                                        child: Padding(
                                          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                                          child: ChannelJoinModal(
                                            client: client,
                                            refresh: () => setState(() {}),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    height: 32.0,
                                    width: 32.0,
                                    child: Icon(
                                      Icons.add,
                                      color: Theme.of(context).colorScheme.onSurface.withAlpha(64 * 3),
                                    ),
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () async => Scaffold.of(context).openEndDrawer(),
                                child: Container(
                                  height: 32.0,
                                  width: 32.0,
                                  child: Icon(
                                    Icons.alternate_email,
                                    size: 20.0,
                                    color: Theme.of(context).colorScheme.onSurface.withAlpha(64 * 3),
                                  ),
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
              body: Stack(
                children: [
                  if (client.channels.isEmpty)
                    SingleChildScrollView(
                      child: Container(
                        constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height),
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                            child: Tutorial(client: client),
                          ),
                        ),
                      ),
                    ),
                  if (client.channels.isNotEmpty)
                    TabBarView(
                      children: [
                        for (var channel in client.channels)
                          ChatView(
                            client: client,
                            channel: channel,
                          ),
                      ],
                    ),
                  FutureBuilder<bool>(
                    future: updateFuture,
                    builder: (context, future) => future.hasData && future.data == true
                        ? Align(
                            alignment: Alignment.topRight,
                            child: SafeArea(
                              top: state is StreamOverlayClosed || horizontal,
                              child: IconButton(
                                icon: Icon(
                                  Icons.system_update,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                onPressed: () async => UpdateModal.searchForUpdate(context),
                              ),
                            ),
                          )
                        : SizedBox(),
                  ),
                ],
              ),
            );

            return state is StreamOverlayClosed
                ? scaffold
                : (horizontal
                    ? Row(
                        children: [
                          Expanded(
                            child: SafeArea(left: false, child: videoPlayer!),
                          ),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(0.0),
                            child: SizedBox(
                              width: 245.0,
                              child: scaffold,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          SafeArea(
                            bottom: false,
                            child: AspectRatio(
                              aspectRatio: 16.0 / 9.0,
                              child: videoPlayer,
                            ),
                          ),
                          Expanded(
                            child: scaffold,
                          ),
                        ],
                      ));
          },
        ),
      );

  @override
  void onChannelStateChange(twitch.Channel channel, twitch.ChannelState state) {
    setState(() {});
  }

  @override
  void onConnectionStateChange(twitch.Connection connection, twitch.ConnectionState state) {
    setState(() {});
  }

  @override
  void onMessage(twitch.Channel? channel, twitch.Message message) {
    if (message.mention) BlocProvider.of<MentionsCubit>(context).add(message);
    if ((BlocProvider.of<Settings>(context).state as SettingsLoaded).notificationOnMention && message.mention) {
      NotificationWrapper.of(context)!.sendNotification(
        payload: message.body,
        title: message.user!.login,
        subtitle: message.body,
      );
    }
  }

  @override
  void onHistoryLoaded(twitch.Channel channel) {}

  @override
  void onWhisper(twitch.Channel channel, twitch.Message message) {
    if ((BlocProvider.of<Settings>(context).state as SettingsLoaded).notificationOnWhisper && message.user!.id != channel.receiver!.credentials!.id) {
      NotificationWrapper.of(context)!.sendNotification(
        payload: message.body,
        title: message.user!.login,
        subtitle: message.body,
      );
    }
  }
}

class Tutorial extends StatelessWidget {
  final twitch.Client client;

  const Tutorial({
    Key? key,
    required this.client,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Icon(Icons.not_started, size: 48.0, color: Theme.of(context).colorScheme.primary),
          Text('Getting started', style: Theme.of(context).textTheme.headline5),
          // Text('To get started, you can join a channel by pressing the + button below.', textAlign: TextAlign.center),
          // SizedBox(height: 32.0),
          // Text('Help', style: Theme.of(context).textTheme.headline5),
          SizedBox(height: 16.0),
          Row(
            children: [
              Icon(Icons.add),
              SizedBox(width: 16.0),
              Expanded(child: Text('The add icon allows you to join channels by typing in their names. You can join multiple channels by separating the names with spaces: "forsen nymn vansamaofficial"')),
            ],
          ),
          SizedBox(height: 16.0),
          Row(
            children: [
              Icon(Icons.menu),
              SizedBox(width: 16.0),
              Expanded(child: Text('The menu icon will open the primary menu of the application. You can also hold-and-slide from the left edge to the right to open it!')),
            ],
          ),
          SizedBox(height: 16.0),
          Row(
            children: [
              Icon(Icons.alternate_email),
              SizedBox(width: 16.0),
              Expanded(child: Text('The email icon will open the mentions menu of the application. You can also hold-and-slide from the right edge to the left to open it!')),
            ],
          ),
          SizedBox(height: 32.0),
          Text('Quick actions', style: Theme.of(context).textTheme.headline5),
          SizedBox(height: 16.0),
          Container(
            constraints: BoxConstraints(maxWidth: 128.0 * 1.5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (context) => AccountPage(
                      client: client,
                    ),
                  )),
                  icon: Icon(Icons.account_circle),
                  label: Text('Add an account'),
                  style: ButtonStyle(
                    shape: MaterialStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(32.0))),
                    padding: MaterialStateProperty.all(EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0 / 2.0)),
                  ),
                ),
                SizedBox(height: 8.0),
                ElevatedButton.icon(
                  onPressed: () async => await client.joinChannels(['#forsen']),
                  icon: Icon(Icons.chat),
                  label: Text('Join #forsen'),
                  style: ButtonStyle(
                    shape: MaterialStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(32.0))),
                    padding: MaterialStateProperty.all(EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0 / 2.0)),
                  ),
                ),
                SizedBox(height: 8.0),
                ElevatedButton.icon(
                  onPressed: () => Scaffold.of(context).openEndDrawer(),
                  icon: Icon(Icons.alternate_email),
                  label: Text('Open mentions'),
                  style: ButtonStyle(
                    shape: MaterialStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(32.0))),
                    padding: MaterialStateProperty.all(EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0 / 2.0)),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}
