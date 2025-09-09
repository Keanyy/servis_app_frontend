import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
// platforma �zel import
// ignore: depend_on_referenced_packages
import 'package:camera_windows/camera_windows.dart';

// YEN� EKLENEN IMPORT'LAR
import 'package:file_picker/file_picker.dart'; // "Farkl� Kaydet" i�in
import 'package:open_file_plus/open_file_plus.dart'; // Dosya a�mak i�in


// --- Global Variables & Constants ---
const String apiUrl = "http://127.0.0.1:5000";
String? _token;
String? _userRole;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (!kIsWeb && Platform.isWindows) {
    CameraWindows.registerWith();
  }

  SharedPreferences prefs = await SharedPreferences.getInstance();
  _token = prefs.getString('token');

  Widget initialScreen = const LoginScreen();
  if (_token != null && !JwtDecoder.isExpired(_token!)) {
    try {
      _userRole = JwtDecoder.decode(_token!)['role'];
      initialScreen = const DeviceListScreen();
    } catch (e) {
      // Token bozuksa veya beklenmedik bir formatta ise login ekran�na y�nlendir
      _token = null;
      await prefs.remove('token');
      initialScreen = const LoginScreen();
    }
  }

  runApp(ServisApp(initialScreen: initialScreen));
}

class ServisApp extends StatelessWidget {
  final Widget initialScreen;
  const ServisApp({super.key, required this.initialScreen});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Teknik Servis',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: initialScreen,
    );
  }
}

// --- Secure HTTP Client with UTF-8 FIX ---
class ApiClient {
  static Future<Map<String, String>> getHeaders() async {
    final headers = {'Content-Type': 'application/json; charset=UTF-8'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  // UTF-8 sorununu ��zmek i�in gelen yan�t� decode eden yard�mc� fonksiyon
  static http.Response _processResponse(http.Response response) {
    try {
      final String decodedBody = utf8.decode(response.bodyBytes);
      return http.Response(decodedBody, response.statusCode, headers: response.headers);
    } catch (e) {
      // E�er decode edilemezse (�rne�in binary veri ise) orijinal yan�t� d�nd�r
      return response;
    }
  }

  static Future<http.Response> get(String endpoint) async {
    final response = await http.get(Uri.parse('$apiUrl$endpoint'), headers: await getHeaders());
    return _processResponse(response);
  }

  static Future<http.Response> post(String endpoint, {Object? body}) async {
    final response = await http.post(Uri.parse('$apiUrl$endpoint'), headers: await getHeaders(), body: jsonEncode(body));
    return _processResponse(response);
  }

  static Future<http.Response> put(String endpoint, {Object? body}) async {
    final response = await http.put(Uri.parse('$apiUrl$endpoint'), headers: await getHeaders(), body: jsonEncode(body));
    return _processResponse(response);
  }

  static Future<http.Response> delete(String endpoint) async {
    final response = await http.delete(Uri.parse('$apiUrl$endpoint'), headers: await getHeaders());
    return _processResponse(response);
  }
}

// ---------------- Login Screen ----------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _login() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kullan�c� ad� ve �ifre bo� olamaz')));
      return;
    }
    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse("$apiUrl/login"),
        headers: {"Content-Type": "application/json"},
        body: json.encode({'username': _usernameController.text, 'password': _passwordController.text}),
      );

      if (response.statusCode == 200) {
        final token = json.decode(response.body)['access_token'];
        _token = token;
        _userRole = JwtDecoder.decode(token)['role'];

        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', token);

        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => const DeviceListScreen()));
      } else {
        final error = json.decode(utf8.decode(response.bodyBytes))['error'] ?? 'Giri� yap�lamad�';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sunucuya ba�lan�lamad�: $e')));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Giri� Yap')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextField(controller: _usernameController, decoration: const InputDecoration(labelText: 'Kullan�c� Ad�', border: OutlineInputBorder())),
                const SizedBox(height: 16),
                TextField(controller: _passwordController, obscureText: true, decoration: const InputDecoration(labelText: '�ifre', border: OutlineInputBorder())),
                const SizedBox(height: 24),
                _isLoading ? const CircularProgressIndicator() : ElevatedButton(onPressed: _login, child: const Text('Giri� Yap')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- Device List Screen ----------------
class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({super.key});
  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  List? devices;
  bool _isLoading = true;
  String? _error;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    fetchDevices();
  }

  Future<void> _logout() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    _token = null;
    _userRole = null;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => const LoginScreen()));
  }

  Future<void> fetchDevices({String? searchQuery}) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    String url = "/devices";
    if (searchQuery != null && searchQuery.trim().length >= 3) {
      url += "?q=${Uri.encodeComponent(searchQuery.trim())}";
    }
    try {
      final response = await ApiClient.get(url);
      if (response.statusCode == 200) {
        if (mounted) setState(() => devices = json.decode(response.body));
      } else {
        if (mounted) setState(() => _error = "Veriler y�klenemedi. Hata kodu: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("API'ye ba�lan�rken hata olu�tu: $e");
      if (mounted) setState(() => _error = "Sunucuya ba�lan�rken bir hata olu�tu. L�tfen ba�lant�n�z� kontrol edin.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  
  void openAddForm() async {
    await Navigator.push(context, MaterialPageRoute(builder: (context) => AddDeviceForm(onSaved: fetchDevices)));
    // Geri d�n�ld���nde listeyi yenile
    fetchDevices(searchQuery: _searchController.text);
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: "Cihaz Ara...",
            border: InputBorder.none,
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _searchController.clear();
                fetchDevices();
              },
            ),
          ),
          onChanged: (value) => fetchDevices(searchQuery: value),
        ),
        actions: [
          if (_userRole == 'admin')
            IconButton(
              icon: const Icon(Icons.people),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const UserManagementScreen())),
              tooltip: 'Kullan�c� Y�netimi',
            ),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(16.0), child: Text(_error!, textAlign: TextAlign.center)))
              : RefreshIndicator(
                  onRefresh: () => fetchDevices(searchQuery: _searchController.text),
                  child: ListView.builder(
                    itemCount: devices?.length ?? 0,
                    itemBuilder: (context, index) {
                      final d = devices![index];
                      final bool isCompleted = d['status'] == 'completed';
                      return ListTile(
                        leading: isCompleted
                            ? const Icon(Icons.check_circle, color: Colors.green)
                            : const Icon(Icons.hourglass_top, color: Colors.orange),
                        title: Text("${d['marka']} ${d['model']}"),
                        subtitle: Text("Kurum: ${d['kurum'] ?? 'N/A'} - Ar�za: ${d['ariza']}"),
                        trailing: Text(d['teklif_durumu'] ?? 'Belirsiz'),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => DeviceDetailScreen(deviceId: d['id'])),
                          );
                          fetchDevices(searchQuery: _searchController.text);
                        },
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(onPressed: openAddForm, child: const Icon(Icons.add)),
    );
  }
}

// ---------------- Device Detail Screen (TAMAMEN G�NCELLEND�) ----------------
class DeviceDetailScreen extends StatefulWidget {
  final int deviceId;
  const DeviceDetailScreen({super.key, required this.deviceId});

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  Map<String, dynamic> device = {};
  bool isLoading = true;
  
  @override
  void initState() {
    super.initState();
    fetchDevice();
  }

  Future<void> fetchDevice() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    final response = await ApiClient.get("/devices/${widget.deviceId}");
    if (mounted) {
      if (response.statusCode == 200) {
        setState(() {
          device = json.decode(response.body);
          isLoading = false;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cihaz detaylar� getirilemedi: ${response.statusCode}')));
        Navigator.pop(context); // Detaylar gelmezse sayfay� kapat
      }
    }
  }

  Future<void> deleteDevice() async {
    final response = await ApiClient.delete("/devices/${widget.deviceId}");
    if (mounted) {
      if (response.statusCode == 200) {
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cihaz silinemedi.')));
      }
    }
  }
  
  Future<void> completeDevice() async {
    final response = await ApiClient.post("/devices/${widget.deviceId}/complete");
    if (mounted) {
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cihaz tamamland� olarak i�aretlendi')));
        fetchDevice();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('��lem tamamlanamad�.')));
      }
    }
  }

  // --- YEN� VE ��LEVSEL PDF �ND�RME FONKS�YONU ---
  Future<void> downloadPdf(String endpoint, String defaultFilename) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$defaultFilename haz�rlan�yor...')),
    );

    try {
      final response = await http.get(
        Uri.parse('$apiUrl$endpoint'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      
      if (response.statusCode == 200) {
        // 1. "Farkl� Kaydet" diyalogunu a�
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'PDF Dosyas�n� Kaydet',
          fileName: defaultFilename,
          type: FileType.custom,
          allowedExtensions: ['pdf'],
        );

        if (outputFile != null) {
          // E�er kullan�c� uzant� girmediyse, .pdf ekle
          if (!outputFile.toLowerCase().endsWith('.pdf')) {
            outputFile += '.pdf';
          }
          final file = File(outputFile);
          await file.writeAsBytes(response.bodyBytes);
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('PDF ba�ar�yla kaydedildi!'),
                action: SnackBarAction(
                  label: 'A�',
                  onPressed: () {
                    OpenFile.open(outputFile);
                  },
                ),
              ),
            );
          }
        }
      } else {
        final error = 'PDF indirilemedi. Sunucu Hatas�: ${response.statusCode}';
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      }
    } catch (e) {
      final error = 'PDF indirilirken bir hata olu�tu: $e';
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final bool isCompleted = device['status'] == 'completed';
    final bool canEdit = _userRole == 'admin' || !isCompleted;

    return Scaffold(
      appBar: AppBar(
        title: Text("${device['marka']} ${device['model']}"),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: "PDF Formlar�",
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem(value: 'teslim_alma', child: Text('Teslim Alma Formu')),
              const PopupMenuItem(value: 'teslim_etme', child: Text('Teslim Etme Formu')),
              const PopupMenuItem(value: 'teklif', child: Text('Teklif Formu')),
            ],
            onSelected: (value) {
              switch (value) {
                case 'teslim_alma':
                  downloadPdf('/devices/${widget.deviceId}/generate-teslim-alma-formu', 'teslim_alma_${widget.deviceId}.pdf');
                  break;
                case 'teslim_etme':
                  downloadPdf('/devices/${widget.deviceId}/generate-teslim-etme-formu', 'teslim_etme_${widget.deviceId}.pdf');
                  break;
                case 'teklif':
                  downloadPdf('/devices/${widget.deviceId}/generate-teklif-formu', 'teklif_${widget.deviceId}.pdf');
                  break;
              }
            },
          ),
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(
                    builder: (context) => EditDeviceForm(deviceId: widget.deviceId)),
                );
                fetchDevice();
              },
            ),
          if (_userRole == 'admin')
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.redAccent),
              onPressed: () => showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text("Silme Onay�"),
                  content: const Text("Bu cihaz� kal�c� olarak silmek istedi�inizden emin misiniz?"),
                  actions: [
                    TextButton(child: const Text("Hay�r"), onPressed: () => Navigator.of(ctx).pop()),
                    TextButton(child: const Text("Evet, Sil"), onPressed: () {
                        Navigator.of(ctx).pop();
                        deleteDevice();
                      },
                    ),
                  ],
                ),
              ),
            ),
          if (!isCompleted)
             IconButton(
              icon: const Icon(Icons.check_circle, color: Colors.green),
              onPressed: () => showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text("��i Tamamla"),
                  content: const Text("Bu kayd� tamamland� olarak i�aretlemek istedi�inizden emin misiniz?"),
                  actions: [
                    TextButton(child: const Text("Hay�r"), onPressed: () => Navigator.of(ctx).pop()),
                    TextButton(child: const Text("Evet, Tamamla"), onPressed: () {
                        Navigator.of(ctx).pop();
                        completeDevice();
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...device.entries
              .where((e) => e.key != 'id' && !e.key.contains('resim') && e.value != null && e.value.toString().isNotEmpty)
              .map((entry) {
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    title: Text(entry.key.toUpperCase().replaceAll('_', ' ')),
                    subtitle: Text(entry.value.toString()),
                  ),
                );
            }).toList(),
          ],
        ),
      ),
    );
  }
}

// ... KODUNUZUN GER� KALAN T�M SINIFLARI (AddDeviceForm, EditDeviceForm, UserManagementScreen, vs.) ...
// Bu s�n�flarda de�i�iklik yapman�za gerek yoktur, mevcut halleriyle kalabilirler.
// L�tfen bu yorum sat�r�n�n alt�ndaki kodlar� kendi projenizden kopyalay�p yap��t�r�n.
// --- ADD DEVICE FORM ---
class AddDeviceForm extends StatefulWidget {
  final Function() onSaved;
  const AddDeviceForm({super.key, required this.onSaved});

  @override
  State<AddDeviceForm> createState() => _AddDeviceFormState();
}

class _AddDeviceFormState extends State<AddDeviceForm> {
  final _formKey = GlobalKey<FormState>();
  Map<String, dynamic> formData = {
    'marka': '', 'model': '', 'seri_no': '', 'kurum': '', 
    'alinma_tarihi': DateTime.now().toIso8601String().substring(0, 10),
    'aksesuar': '', 'ariza': '', 'tespit': '', 'personel': '',
    'maliyet': 0.0, 'servis_ucreti': 0.0,
    'teklif_durumu': 'Teklif Bekliyor',
    'iletisim_kisi': '', 'iletisim_tel': ''
  };

  final List<String> _teklifDurumlari = ['Teklif Bekliyor', 'Teklif Verildi', 'Onayland�', 'Reddedildi', 'Fatura Edildi'];

  Future<void> saveDevice() async {
    final response = await ApiClient.post("/devices", body: formData);
    if (mounted) {
      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cihaz ba�ar�yla eklendi')));
        widget.onSaved();
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cihaz eklenirken bir hata olu�tu')));
      }
    }
  }

  Widget buildTextField(String label, String key, {bool isNumeric = false, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        keyboardType: isNumeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        maxLines: maxLines,
        onSaved: (value) {
          if (isNumeric) {
            formData[key] = double.tryParse(value ?? '0') ?? 0.0;
          } else {
            formData[key] = value;
          }
        },
      ),
    );
  }

  Widget buildDatePickerField(String label, String key) {
    // Controller'� state i�inde tan�mla
    final controller = TextEditingController(text: formData[key]);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () async {
              DateTime? pickedDate = await showDatePicker(
                context: context,
                initialDate: DateTime.tryParse(formData[key] ?? '') ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2101),
              );
              if (pickedDate != null) {
                setState(() {
                   final formattedDate = pickedDate.toIso8601String().substring(0, 10);
                   formData[key] = formattedDate;
                   controller.text = formattedDate;
                });
              }
            },
          ),
        ),
        readOnly: true,
        onSaved: (value) => formData[key] = value,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Yeni Cihaz Ekle")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              buildTextField("Marka", "marka"),
              buildTextField("Model", "model"),
              buildTextField("Seri No", "seri_no"),
              buildTextField("Kurum", "kurum"),
              buildTextField("�leti�im Ki�isi", "iletisim_kisi"),
              buildTextField("�leti�im Telefonu", "iletisim_tel"),
              buildDatePickerField("Al�nma Tarihi", "alinma_tarihi"),
              buildTextField("Aksesuar", "aksesuar"),
              buildTextField("Ar�za", "ariza", maxLines: 3),
              buildTextField("Servis Tespiti", "tespit", maxLines: 3),
              buildTextField("�lgili Personel", "personel"),
              DropdownButtonFormField<String>(
                value: formData['teklif_durumu'],
                decoration: const InputDecoration(labelText: 'Teklif Durumu', border: OutlineInputBorder()),
                items: _teklifDurumlari.map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (newValue) {
                  setState(() {
                    formData['teklif_durumu'] = newValue;
                  });
                },
                onSaved: (value) => formData['teklif_durumu'] = value,
              ),
              const SizedBox(height: 8),
              buildTextField("Maliyet", "maliyet", isNumeric: true),
              buildTextField("Servis �creti", "servis_ucreti", isNumeric: true),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()){
                    _formKey.currentState!.save();
                    saveDevice();
                  }
                },
                child: const Text("Kaydet"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// --- EDIT DEVICE FORM ---
class EditDeviceForm extends StatefulWidget {
  final int deviceId;
  const EditDeviceForm({super.key, required this.deviceId});
  @override
  State<EditDeviceForm> createState() => _EditDeviceFormState();
}
class _EditDeviceFormState extends State<EditDeviceForm> {
  final _formKey = GlobalKey<FormState>();
  Map<String, dynamic> formData = {};
  bool isLoading = true;
  final List<String> _teklifDurumlari = ['Teklif Bekliyor', 'Teklif Verildi', 'Onayland�', 'Reddedildi', 'Fatura Edildi'];

  @override
  void initState() {
    super.initState();
    fetchDeviceData();
  }

  Future<void> fetchDeviceData() async {
    final response = await ApiClient.get("/devices/${widget.deviceId}");
    if (mounted) {
      if (response.statusCode == 200) {
        setState(() {
          formData = json.decode(response.body);
          isLoading = false;
        });
      }
    }
  }

  Future<void> updateDevice() async {
    final response = await ApiClient.put("/devices/${widget.deviceId}", body: formData);
    if (mounted) {
       if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cihaz ba�ar�yla g�ncellendi')));
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cihaz g�ncellenirken bir hata olu�tu')));
      }
    }
  }

  Widget buildTextField(String label, String key, {bool isNumeric = false, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        initialValue: formData[key]?.toString(),
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        keyboardType: isNumeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        maxLines: maxLines,
        onSaved: (value) {
          if (isNumeric) {
            formData[key] = double.tryParse(value ?? '0') ?? 0.0;
          } else {
            formData[key] = value;
          }
        },
      ),
    );
  }

  Widget buildDatePickerField(String label, String key) {
    final controller = TextEditingController(text: formData[key]);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () async {
              DateTime? pickedDate = await showDatePicker(
                context: context,
                initialDate: DateTime.tryParse(formData[key] ?? '') ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2101),
              );
              if (pickedDate != null) {
                setState(() {
                  final formattedDate = pickedDate.toIso8601String().substring(0, 10);
                  formData[key] = formattedDate;
                  controller.text = formattedDate;
                });
              }
            },
          ),
        ),
        readOnly: true,
        onSaved: (value) => formData[key] = value,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text("Cihaz� D�zenle")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              buildTextField("Marka", "marka"),
              buildTextField("Model", "model"),
              buildTextField("Seri No", "seri_no"),
              buildTextField("Kurum", "kurum"),
              buildTextField("�leti�im Ki�isi", "iletisim_kisi"),
              buildTextField("�leti�im Telefonu", "iletisim_tel"),
              buildDatePickerField("Al�nma Tarihi", "alinma_tarihi"),
              buildTextField("Aksesuar", "aksesuar"),
              buildTextField("Ar�za", "ariza", maxLines: 3),
              buildTextField("Servis Tespiti", "tespit", maxLines: 3),
              buildTextField("�lgili Personel", "personel"),
              DropdownButtonFormField<String>(
                value: formData['teklif_durumu'],
                decoration: const InputDecoration(labelText: 'Teklif Durumu', border: OutlineInputBorder()),
                items: _teklifDurumlari.map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (newValue) {
                  setState(() {
                    formData['teklif_durumu'] = newValue;
                  });
                },
                onSaved: (value) => formData['teklif_durumu'] = value,
              ),
              const SizedBox(height: 8),
              buildTextField("Maliyet", "maliyet", isNumeric: true),
              buildTextField("Servis �creti", "servis_ucreti", isNumeric: true),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()){
                    _formKey.currentState!.save();
                    updateDevice();
                  }
                },
                child: const Text("G�ncelle"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// --- USER MANAGEMENT ---
class User {
  final int id;
  final String username;
  final String role;

  User({required this.id, required this.username, required this.role});

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      role: json['role'],
    );
  }
}
class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}
class _UserManagementScreenState extends State<UserManagementScreen> {
  List<User> users = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchUsers();
  }

  Future<void> fetchUsers() async {
    try {
      final response = await ApiClient.get("/users");
      if (mounted) {
        if (response.statusCode == 200) {
          setState(() {
            users = (json.decode(response.body) as List)
                .map((data) => User.fromJson(data))
                .toList();
            isLoading = false;
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Kullan�c�lar y�klenirken hata olu�tu')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sunucuya ba�lan�rken hata olu�tu')),
        );
      }
    }
  }

  Future<void> addUser(String username, String password, String role) async {
    try {
      final response = await ApiClient.post("/users", body: {
        'username': username,
        'password': password,
        'role': role,
      });
      
      if (mounted) {
        if (response.statusCode == 201) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Kullan�c� ba�ar�yla eklendi')),
          );
          fetchUsers();
        } else {
          final error = json.decode(response.body)['error'] ?? 'Kullan�c� eklenirken hata olu�tu';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sunucuya ba�lan�rken hata olu�tu')),
        );
      }
    }
  }

  Future<void> deleteUser(int userId) async {
    try {
      final response = await ApiClient.delete("/users/$userId");
      if (mounted) {
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Kullan�c� ba�ar�yla silindi')),
          );
          fetchUsers();
        } else {
          final error = json.decode(response.body)['error'] ?? 'Kullan�c� silinirken hata olu�tu';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sunucuya ba�lan�rken hata olu�tu')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_userRole != 'admin') {
      return Scaffold(
        appBar: AppBar(title: const Text('Kullan�c� Y�netimi')),
        body: const Center(child: Text('Bu sayfaya eri�im izniniz yok')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Kullan�c� Y�netimi')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: users.length,
              itemBuilder: (context, index) {
                final user = users[index];
                return ListTile(
                  title: Text(user.username),
                  subtitle: Text(user.role),
                  trailing: user.username != 'admin'
                      ? IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text("Silme Onay�"),
                                content: Text("${user.username} kullan�c�s�n� silmek istedi�inizden emin misiniz?"),
                                actions: [
                                  TextButton(child: const Text("Hay�r"), onPressed: () => Navigator.of(ctx).pop()),
                                  TextButton(child: const Text("Evet, Sil"), onPressed: () {
                                    Navigator.of(ctx).pop();
                                    deleteUser(user.id);
                                  }),
                                ],
                              ),
                            );
                          },
                        )
                      : null,
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => AddUserDialog(onAdd: addUser),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
class AddUserDialog extends StatefulWidget {
  final Function(String, String, String) onAdd;
  const AddUserDialog({super.key, required this.onAdd});

  @override
  State<AddUserDialog> createState() => _AddUserDialogState();
}
class _AddUserDialogState extends State<AddUserDialog> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  String _selectedRole = 'user';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Yeni Kullan�c� Ekle'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _usernameController,
            decoration: const InputDecoration(labelText: 'Kullan�c� Ad�'),
          ),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: '�ifre'),
          ),
          DropdownButtonFormField(
            value: _selectedRole,
            items: ['user', 'admin']
                .map((role) => DropdownMenuItem(
                      value: role,
                      child: Text(role == 'admin' ? 'Y�netici' : 'Kullan�c�'),
                    ))
                .toList(),
            onChanged: (value) {
              setState(() {
                _selectedRole = value!;
              });
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('�ptal'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Kullan�c� ad� ve �ifre bo� olamaz')),
              );
              return;
            }
            
            widget.onAdd(
              _usernameController.text,
              _passwordController.text,
              _selectedRole,
            );
            Navigator.pop(context);
          },
          child: const Text('Ekle'),
        ),
      ],
    );
  }
}
