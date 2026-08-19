import 'package:flutter/material.dart';

/// The route the app holds on while auth is still resolving, on a device some
/// account already has a stake in.
///
/// Nothing else can be shown safely in that window. The album would mount and
/// run the owner's query on a device that may turn out to be refused, and the
/// lock screen would tell an owner opening the app offline that their own
/// pottery belongs to somebody else — a session-less launch looks identical
/// either way until auth answers. So this shows nothing at all: bare scaffold
/// ground, the same cream the departing splash sits on, for the moment it
/// takes the redirect to learn which of the two this is.
class StartingScreen extends StatelessWidget {
  const StartingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: SizedBox.expand());
  }
}
