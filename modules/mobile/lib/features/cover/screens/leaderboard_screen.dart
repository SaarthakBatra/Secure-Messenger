import 'package:flutter/material.dart';

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mockUsers = List.generate(100, (index) {
      if (index == 23) {
        return {'name': 'You', 'xp': 950, 'avatar': Icons.sentiment_satisfied_rounded, 'isMe': true};
      }
      final xp = 1272 - (index * 14); // Scaled so index 23 is exactly 950 XP
      final names = ['Alex', 'Sam', 'Jordan', 'Taylor', 'Casey', 'Morgan', 'Jamie', 'Riley', 'Avery', 'Quinn', 'Harper', 'Rowan', 'Charlie', 'Drew', 'Skyler'];
      final avatars = [Icons.person_rounded, Icons.face_rounded, Icons.sentiment_neutral_rounded, Icons.person_outline_rounded, Icons.face_retouching_natural_rounded, Icons.person_2_rounded, Icons.person_3_rounded, Icons.person_4_rounded];
      
      return {
        'name': '${names[index % names.length]} ${(index * 7) % 99}',
        'xp': xp,
        'avatar': avatars[index % avatars.length],
        'isMe': false,
      };
    });

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Silver League',
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFC0C0C0).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFC0C0C0).withOpacity(0.5)),
                  ),
                  child: const Text('Top 15 Advance', style: TextStyle(color: Color(0xFFC0C0C0), fontWeight: FontWeight.bold)),
                )
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: mockUsers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final user = mockUsers[index];
                final isMe = user['isMe'] == true;
                final rank = index + 1;

                Color rankColor;
                if (rank == 1) rankColor = const Color(0xFFFFD700);
                else if (rank == 2) rankColor = const Color(0xFFC0C0C0);
                else if (rank == 3) rankColor = const Color(0xFFCD7F32);
                else rankColor = Colors.white54;

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isMe ? const Color(0xFF00E676).withOpacity(0.1) : Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isMe ? const Color(0xFF00E676).withOpacity(0.3) : Colors.white.withOpacity(0.05)),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 30,
                        child: Text(
                          '$rank',
                          style: TextStyle(color: rankColor, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      CircleAvatar(
                        backgroundColor: Colors.white.withOpacity(0.1),
                        child: Icon(user['avatar'] as IconData, color: Colors.white70),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          user['name'] as String,
                          style: TextStyle(color: isMe ? const Color(0xFF00E676) : Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Text(
                        '${user['xp']} XP',
                        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
