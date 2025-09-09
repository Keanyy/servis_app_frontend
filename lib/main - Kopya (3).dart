import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

// --- Global Variables & Constants ---
// Windows masaüstü uygulamasý için bu adres doðrudur.
// Mobil emülatör/cihaz için bilgisayarýnýzýn yerel IP adresini yazmalýsýnýz.
const String apiUrl = "http://127.0.0.1:5000";
String? _token;
String? _userRole;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences prefs = await SharedPreferences.getInstance();
  _token = prefs.getString('token');

  Widget initialScreen = const LoginScreen();
  if (_token != null && !JwtDecoder.isExpired(_token!)) {
    _userRole = JwtDecoder.decode(_token!)['role'];
    initialScreen = const DeviceListScreen();
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
      theme: ThemeData(primarySwatch: Colors.blue),
      home: initialScreen,
    );
  }
}

// --- Secure HTTP Client with UTF-8 FIX ---
class ApiClient {
  static Future<Map<String, String>> getHeaders() async {
    final headers = {'Content-Type': 'application/json'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  static http.Response _processResponse(http.Response response) {
    final String decodedBody = utf8.decode(response.bodyBytes);
    return http.Response(decodedBody, response.statusCode, headers: response.headers);
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kullanýcý adý ve þifre boþ olamaz')));
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
        final error = json.decode(response.body)['error'] ?? 'Giriþ yapýlamadý';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sunucuya baðlanýlamadý')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Giriþ Yap')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(controller: _usernameController, decoration: const InputDecoration(labelText: 'Kullanýcý Adý')),
            const SizedBox(height: 16),
            TextField(controller: _passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Þifre')),
            const SizedBox(height: 24),
            _isLoading ? const CircularProgressIndicator() : ElevatedButton(onPressed: _login, child: const Text('Giriþ Yap')),
          ],
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
    setState(() {
      _isLoading = true;
      _error = null;
    });

    String url = "/devices";
    if (searchQuery != null && searchQuery.length >= 3) {
      url += "?q=$searchQuery";
    }
    try {
      final response = await ApiClient.get(url);
      if (response.statusCode == 200) {
        setState(() => devices = json.decode(response.body));
      } else {
        setState(() => _error = "Veriler yüklenemedi. Hata kodu: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("API'ye baðlanýrken hata oluþtu: $e");
      setState(() => _error = "Sunucuya baðlanýrken bir hata oluþtu. Lütfen baðlantýnýzý kontrol edin.");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void openAddForm() {
    Navigator.push(context, MaterialPageRoute(builder: (context) => AddDeviceForm(onSaved: fetchDevices)));
  }

  @override
  Widget build(BuildContext context) {
    double toplamMaliyet = 0.0;
    double toplamServis = 0.0;
    double netGelir = 0.0;
    if (devices != null) {
      toplamMaliyet = devices!.fold(0.0, (sum, d) => sum + (d['maliyet'] ?? 0.0));
      toplamServis = devices!.fold(0.0, (sum, d) => sum + (d['servis_ucreti'] ?? 0.0));
      netGelir = toplamServis - toplamMaliyet;
    }

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
        actions: [IconButton(icon: const Icon(Icons.logout), onPressed: _logout)],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
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
                                  : const Icon(Icons.hourglass_top),
                              title: Text("${d['marka']} ${d['model']}"),
                              subtitle: Text("Arýza: ${d['ariza']}"),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => DeviceDetailScreen(deviceId: d['id'])),
                                );
                                fetchDevices();
                              },
                            );
                          },
                        ),
                      ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Toplam Maliyet: ${toplamMaliyet.toStringAsFixed(2)}"),
                    Text("Toplam Servis Ücreti: ${toplamServis.toStringAsFixed(2)}"),
                    Text("Net Gelir: ${netGelir.toStringAsFixed(2)}"),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: openAddForm, child: const Icon(Icons.add)),
    );
  }
}

// ---------------- Device Detail Screen ----------------
class DeviceDetailScreen extends StatefulWidget {
  final int deviceId;
  const DeviceDetailScreen({super.key, required this.deviceId});

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  Map<String, dynamic> device = {};
  bool isLoading = true;
  File? _selectedImage;

  @override
  void initState() {
    super.initState();
    fetchDevice();
  }

  Future<void> fetchDevice() async {
    final response = await ApiClient.get("/devices/${widget.deviceId}");
    if (response.statusCode == 200) {
      setState(() {
        device = json.decode(response.body);
        isLoading = false;
      });
    }
  }

  Future<void> deleteDevice() async {
    final response = await ApiClient.delete("/devices/${widget.deviceId}");
    if (response.statusCode == 200) Navigator.pop(context);
  }
  
  Future<void> completeDevice() async {
    final response = await ApiClient.post("/devices/${widget.deviceId}/complete");
    if (response.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cihaz tamamlandý olarak iþaretlendi')));
      fetchDevice();
    }
  }

  Future<void> _pickImage(int index, bool isRepair) async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() => _selectedImage = File(pickedFile.path));
      await uploadImage(index, isRepair);
    }
  }

  Future<void> uploadImage(int index, bool isRepair) async {
    if (_selectedImage == null) return;
    var request = http.MultipartRequest('POST', Uri.parse("$apiUrl/devices/${widget.deviceId}/upload"));
    request.headers['Authorization'] = 'Bearer $_token';
    request.fields['index'] = isRepair ? (index + 3).toString() : index.toString();
    request.files.add(await http.MultipartFile.fromPath('file', _selectedImage!.path));

    final response = await request.send();
    if (response.statusCode == 200) {
      debugPrint("Resim baþarýyla yüklendi");
      fetchDevice();
    } else {
      debugPrint("Resim yüklenirken hata oluþtu");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final bool isCompleted = device['status'] == 'completed';
    final bool canEdit = _userRole == 'admin' || !isCompleted;

    return Scaffold(
      appBar: AppBar(
        title: Text("${device['marka']} ${device['model']} Detay"),
        actions: [
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
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text("Silme Onayý"),
                  content: const Text("Bu cihazý kalýcý olarak silmek istediðinizden emin misiniz?"),
                  actions: [
                    TextButton(child: const Text("Hayýr"), onPressed: () => Navigator.of(ctx).pop()),
                    TextButton(child: const Text("Evet, Sil"), onPressed: () {
                        Navigator.of(ctx).pop();
                        deleteDevice();
                      },
                    ),
                  ],
                ),
              ),
            ),
          if (_userRole == 'user' && !isCompleted)
             IconButton(
              icon: const Icon(Icons.check_circle, color: Colors.green),
              onPressed: () => showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text("Ýþi Tamamla"),
                  content: const Text("Bu kaydý tamamlandý olarak iþaretlemek istediðinizden emin misiniz? Bu iþlem geri alýnamaz."),
                  actions: [
                    TextButton(child: const Text("Hayýr"), onPressed: () => Navigator.of(ctx).pop()),
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
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            ...device.entries.where((e) => e.key != 'id' && !e.key.contains('resim')).map((entry) {
              return ListTile(
                title: Text(entry.key.toUpperCase().replaceAll('_', ' ')),
                subtitle: Text(entry.value.toString()),
              );
            }).toList(),
            const SizedBox(height: 20),
            const Text("Cihaz Resimleri", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                buildImageContainer(device['resim1'], 1, false, canEdit),
                buildImageContainer(device['resim2'], 2, false, canEdit),
                buildImageContainer(device['resim3'], 3, false, canEdit),
              ],
            ),
            const SizedBox(height: 20),
            const Text("Onarým Sonrasý Resimler", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                buildImageContainer(device['onarim_resim1'], 1, true, canEdit),
                buildImageContainer(device['onarim_resim2'], 2, true, canEdit),
                buildImageContainer(device['onarim_resim3'], 3, true, canEdit),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget buildImageContainer(String? imagePath, int index, bool isRepair, bool canEdit) {
    return InkWell(
      onTap: canEdit ? () => _pickImage(index, isRepair) : null,
      child: Card(
        child: imagePath != null
            ? Image.network("$apiUrl/$imagePath", fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => const Icon(Icons.error))
            : Center(child: Icon(Icons.add_a_photo, color: canEdit ? Colors.black : Colors.grey)),
      ),
    );
  }
}

// ---------------- Add Device Form ----------------
class AddDeviceForm extends StatefulWidget {
  final Function() onSaved;
  const AddDeviceForm({super.key, required this.onSaved});

  @override
  State<AddDeviceForm> createState() => _AddDeviceFormState();
}

class _AddDeviceFormState extends State<AddDeviceForm> {
  final _formKey = GlobalKey<FormState>();
  Map<String, dynamic> formData = {
    'marka': '', 'model': '', 'seri_no': '', 'kurum': '', 'alinma_tarihi': '',
    'aksesuar': '', 'ariza': '', 'tespit': '', 'personel': '',
    'maliyet': 0.0, 'servis_ucreti': 0.0
  };

  Future<void> saveDevice() async {
    final response = await ApiClient.post("/devices", body: formData);
    if (response.statusCode == 201) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cihaz baþarýyla eklendi')));
      widget.onSaved();
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cihaz eklenirken bir hata oluþtu')));
    }
  }

  Widget buildTextField(String label, String key, {bool isNumeric = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: TextEditingController(text: formData[key]),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () async {
              DateTime? pickedDate = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2101),
              );
              if (pickedDate != null) {
                setState(() => formData[key] = pickedDate.toIso8601String().substring(0, 10));
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
              buildDatePickerField("Alýnma Tarihi", "alinma_tarihi"),
              buildTextField("Aksesuar", "aksesuar"),
              buildTextField("Arýza", "ariza"),
              buildTextField("Servis Tespiti", "tespit"),
              buildTextField("Ýlgili Personel", "personel"),
              buildTextField("Maliyet", "maliyet", isNumeric: true),
              buildTextField("Servis Ücreti", "servis_ucreti", isNumeric: true),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  _formKey.currentState!.save();
                  saveDevice();
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

// ---------------- Edit Device Form ----------------
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

  @override
  void initState() {
    super.initState();
    fetchDeviceData();
  }

  Future<void> fetchDeviceData() async {
    final response = await ApiClient.get("/devices/${widget.deviceId}");
    if (response.statusCode == 200) {
      setState(() {
        formData = json.decode(response.body);
        isLoading = false;
      });
    }
  }

  Future<void> updateDevice() async {
    final response = await ApiClient.put("/devices/${widget.deviceId}", body: formData);
    if (response.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cihaz baþarýyla güncellendi')));
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cihaz güncellenirken bir hata oluþtu')));
    }
  }

  Widget buildTextField(String label, String key, {bool isNumeric = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        initialValue: formData[key]?.toString(),
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
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
    // We need to use a controller to dynamically update the date picker's text field
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
                initialDate: formData[key] != null ? DateTime.tryParse(formData[key]) ?? DateTime.now() : DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2101),
              );
              if (pickedDate != null) {
                setState(() {
                  String formattedDate = pickedDate.toIso8601String().substring(0, 10);
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: Text("${formData['marka']} ${formData['model']} Düzenle")),
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
              buildDatePickerField("Alýnma Tarihi", "alinma_tarihi"),
              buildTextField("Aksesuar", "aksesuar"),
              buildTextField("Arýza", "ariza"),
              buildTextField("Servis Tespiti", "tespit"),
              buildDatePickerField("Geri Teslim Tarihi", "geri_teslim_tarihi"),
              buildTextField("Ýlgili Personel", "personel"),
              buildTextField("Maliyet", "maliyet", isNumeric: true),
              buildTextField("Servis Ücreti", "servis_ucreti", isNumeric: true),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  _formKey.currentState!.save();
                  updateDevice();
                },
                child: const Text("Güncelle"),
              )
            ],
          ),
        ),
      ),
    );
  }
}