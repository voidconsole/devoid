import 'package:devoid/theme/app_colors.dart';
import 'package:devoid/widgets/squircle_border.dart';
import 'package:flutter/material.dart';

class NetworkTile extends StatelessWidget {
  final String icon;
  final String name;
  final VoidCallback? onTap;
  final bool isUnread;

  const NetworkTile({
    Key? key,
    required this.icon,
    required this.name,
    this.onTap,
    this.isUnread = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: ShapeDecoration(
                    color: primaryColor,
                    shape: SquircleBorder(radius: 17),
                  ),
                  child: Center(
                    child: Text(
                      icon,
                      style: TextStyle(
                        color: scaffoldBackgroundColor,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 25),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      color: primaryColor,
                      fontSize: 20,
                      fontWeight: isUnread ? FontWeight.w800 : FontWeight.w400,
                    ),
                  ),
                ),
                if (isUnread)
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: primaryColor,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
          Divider(
            indent: 60,
            endIndent: 60,
            color: primaryColor.withAlpha(7),
            thickness: 0,
          ),
        ],
      ),
    );
  }
}
