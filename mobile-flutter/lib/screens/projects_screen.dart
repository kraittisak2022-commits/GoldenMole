import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/land_project.dart';
import '../services/project_service.dart';
import '../utils/mobile_error_screen_tracker.dart';
import '../utils/mobile_screen_ids.dart';
import '../widgets/list_page_skeleton.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key, required this.service});

  final ProjectService service;

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  late Future<List<LandProject>> _projectsFuture;
  final TextEditingController _searchController = TextEditingController();
  String _statusFilter = 'All';

  @override
  void initState() {
    super.initState();
    MobileErrorScreenTracker.set(
      page: 'โครงการ',
      pageId: MobileScreenIds.pageProjects,
      stepId: MobileScreenIds.stepProjectsList,
    );
    _projectsFuture = widget.service.fetchProjects();
  }

  void _reload() {
    setState(() {
      _projectsFuture = widget.service.fetchProjects();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! > 550) {
          Navigator.maybePop(context);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F4FA),
        appBar: AppBar(
          title: Text(
            'โครงการ',
            style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
          ),
          actions: [
            IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
          ],
        ),
        body: FutureBuilder<List<LandProject>>(
          future: _projectsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const ListPageSkeleton(rowCount: 6);
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'โหลดโครงการไม่สำเร็จ\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              );
            }
            final all = snapshot.data ?? const [];
            final q = _searchController.text.trim().toLowerCase();
            final projects = all.where((p) {
              final passStatus =
                  _statusFilter == 'All' || p.status == _statusFilter;
              if (!passStatus) return false;
              if (q.isEmpty) return true;
              return p.name.toLowerCase().contains(q) ||
                  p.status.toLowerCase().contains(q);
            }).toList();

            return Column(
              children: [
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        style: GoogleFonts.kanit(),
                        decoration: InputDecoration(
                          hintText: 'ค้นหาโครงการ',
                          hintStyle: GoogleFonts.kanit(),
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: const Color(0xFFF7FAFF),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: Text(
                                'ทั้งหมด',
                                style: GoogleFonts.kanit(),
                              ),
                              selected: _statusFilter == 'All',
                              onSelected: (_) =>
                                  setState(() => _statusFilter = 'All'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: Text('Active', style: GoogleFonts.kanit()),
                              selected: _statusFilter == 'Active',
                              onSelected: (_) =>
                                  setState(() => _statusFilter = 'Active'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: Text('Closed', style: GoogleFonts.kanit()),
                              selected: _statusFilter == 'Closed',
                              onSelected: (_) =>
                                  setState(() => _statusFilter = 'Closed'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: projects.isEmpty
                      ? Center(
                          child: Text(
                            'ไม่พบโครงการ',
                            style: GoogleFonts.kanit(),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                          itemCount: projects.length,
                          itemBuilder: (context, index) {
                            final p = projects[index];
                            final isActive = p.status.toLowerCase() == 'active';
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xFFDBECFF),
                                  child: Icon(
                                    Icons.location_city_outlined,
                                    color: const Color(0xFF1565C0),
                                  ),
                                ),
                                title: Text(
                                  p.name,
                                  style: GoogleFonts.kanit(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  '${p.status}${p.fullPrice != null ? ' • ${p.fullPrice!.toStringAsFixed(0)} บาท' : ''}',
                                  style: GoogleFonts.kanit(),
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        (isActive ? Colors.green : Colors.grey)
                                            .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    p.status,
                                    style: GoogleFonts.kanit(
                                      fontWeight: FontWeight.w600,
                                      color: isActive
                                          ? Colors.green
                                          : Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
