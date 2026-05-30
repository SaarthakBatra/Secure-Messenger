import 'package:flutter/material.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const CircleAvatar(
              radius: 50,
              backgroundColor: Color(0xFF1F3A45),
              child: Icon(Icons.person_rounded, size: 50, color: Color(0xFF00E676)),
            ),
            const SizedBox(height: 16),
            const Text('You', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Joined May 2026', style: TextStyle(color: Colors.white54, fontSize: 14)),
            const SizedBox(height: 32),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.5,
              children: [
                _buildStatCard('Total XP', '950', Icons.flash_on_rounded, const Color(0xFFFF9100)),
                _buildStatCard('Current Streak', '4', Icons.local_fire_department_rounded, const Color(0xFFFF3D00)),
                _buildStatCard('Top League', 'Silver', Icons.emoji_events_rounded, const Color(0xFFC0C0C0)),
                _buildStatCard('Words Learned', '142', Icons.school_rounded, const Color(0xFF00B0FF)),
              ],
            ),
            const SizedBox(height: 32),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Achievements', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 16),
            Column(
              children: [
                _buildAchievementRow('Early Bird', 'Complete a lesson before 8 AM', Icons.wb_sunny_rounded, const Color(0xFFFFD700)),
                const SizedBox(height: 12),
                _buildAchievementRow('Sharpshooter', 'Complete a lesson with no mistakes', Icons.my_location_rounded, const Color(0xFF00E676)),
                const SizedBox(height: 12),
                _buildAchievementRow('Weekend Warrior', 'Complete a lesson on Saturday and Sunday', Icons.calendar_month_rounded, const Color(0xFFE040FB), isLocked: true),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildAchievementRow(String title, String description, IconData icon, Color color, {bool isLocked = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isLocked ? Colors.transparent : Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isLocked ? Colors.white.withOpacity(0.05) : color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isLocked ? Colors.white.withOpacity(0.05) : color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(isLocked ? Icons.lock_rounded : icon, color: isLocked ? Colors.white38 : color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: isLocked ? Colors.white54 : Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(description, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
