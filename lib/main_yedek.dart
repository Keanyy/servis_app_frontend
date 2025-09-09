import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

void main() {
  runApp(const ServisApp());
}

class ServisApp extends StatelessWidget {
  const ServisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Teknik Servis',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const DeviceListScreen(),
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
  List devices = [];

  @override
  void initState() {
    super.initState();
    fetchDevices();
  }

  Future<void> fetchDevices() async {
    final response =
        await http.get(Uri.parse("http://127.0.0.1:5000/devices"));
    if (response.statusCode == 200) {
      setState(() {
        devices = json.decode(response.body);
      });
    }
  }

  void openAddForm() {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) => AddDeviceForm(onSaved: fetchDevices)),
    );
  }

  @override
  Widget build(BuildContext context) {
    double toplamMaliyet =
        devices.fold(0, (sum, d) => sum + (d['maliyet'] ?? 0));
    double toplamServis =
        devices.fold(0, (sum, d) => sum + (d['servis_ucreti'] ?? 0));
    double netGelir = toplamServis - toplamMaliyet;

    return Scaffold(
      appBar: AppBar(title: const Text("Cihaz Listesi")),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: fetchDevices,
              child: ListView.builder(
                itemCount: devices.length,
                itemBuilder: (context, index) {
                  final d = devices[index];
                  return ListTile(
                    title: Text("${d['marka']} ${d['model']}"),
                    subtitle: Text("Arýza: ${d['ariza']}"),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              DeviceDetailScreen(deviceId: d['id']),
                        ),
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
                    Text("Toplam Maliyet: $toplamMaliyet"),
                    Text("Toplam Servis Ücreti: $toplamServis"),
                    Text("Net Gelir: $netGelir"),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: openAddForm,
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ---------------- Add Device Form ----------------
class AddDeviceForm extends StatefulWidget {
  final VoidCallback onSaved;
  const AddDeviceForm({super.key, required this.onSaved});

  @override
  State<AddDeviceForm> createState() => _AddDeviceFormState();
}

class _AddDeviceFormState extends State<AddDeviceForm> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, dynamic> formData = {};
  final TextEditingController _alinmaController = TextEditingController();
  final TextEditingController _geriTeslimController = TextEditingController();

  Future<void> saveDevice() async {
    final response = await http.post(
      Uri.parse("http://127.0.0.1:5000/devices"),
      headers: {"Content-Type": "application/json"},
      body: json.encode({
        "marka": formData["marka"],
        "model": formData["model"],
        "seri_no": formData["seri_no"],
        "kurum": formData["kurum"],
        "alinma_tarihi": _alinmaController.text,
        "aksesuar": formData["aksesuar"],
        "ariza": formData["ariza"],
        "tespit": formData["tespit"],
        "geri_teslim_tarihi": _geriTeslimController.text,
        "personel": formData["personel"],
        "maliyet": double.tryParse(formData["maliyet"] ?? "0") ?? 0,
        "servis_ucreti": double.tryParse(formData["servis_ucreti"] ?? "0") ?? 0,
      }),
    );

    if (response.statusCode == 200) {
      widget.onSaved();
      Navigator.pop(context);
    }
  }

  Widget buildTextField(String label, String key, {String? initialValue}) {
    return TextFormField(
      initialValue: initialValue,
      decoration: InputDecoration(labelText: label),
      onSaved: (value) => formData[key] = value,
    );
  }

  Widget buildDatePickerField(String label, TextEditingController controller) {
    return InkWell(
      onTap: () async {
        DateTime? pickedDate = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (pickedDate != null) {
          String formattedDate =
              "${pickedDate.year}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.day.toString().padLeft(2, '0')}";
          controller.text = formattedDate;
        }
      },
      child: IgnorePointer(
        child: TextFormField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: const Icon(Icons.calendar_today),
          ),
        ),
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
              buildDatePickerField("Alýnma Tarihi", _alinmaController),
              buildTextField("Aksesuar", "aksesuar"),
              buildTextField("Arýza", "ariza"),
              buildTextField("Servis Tespiti", "tespit"),
              buildDatePickerField("Geri Teslim Tarihi", _geriTeslimController),
              buildTextField("Ýlgili Personel", "personel"),
              buildTextField("Maliyet", "maliyet"),
              buildTextField("Servis Ücreti", "servis_ucreti"),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  _formKey.currentState!.save();
                  saveDevice();
                },
                child: const Text("Kaydet"),
              )
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- Device Detail Screen ----------------
class DeviceDetailScreen extends StatefulWidget {
  final int deviceId;
  DeviceDetailScreen({super.key, required this.deviceId});

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  final ImagePicker picker = ImagePicker();
  Map<String, dynamic> device = {};
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchDeviceDetails();
  }

  Future<void> fetchDeviceDetails() async {
    setState(() {
      isLoading = true;
    });
    final response = await http.get(Uri.parse('http://127.0.0.1:5000/devices/${widget.deviceId}'));
    if (response.statusCode == 200) {
      setState(() {
        device = json.decode(response.body);
        isLoading = false;
      });
    } else {
      setState(() {
        isLoading = false;
      });
      // Handle error appropriately
    }
  }

  Future<void> pickImage(int index) async {
    ImageSource? source = await showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Resim kaynaðý seçin"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, ImageSource.camera),
            child: const Text("Kamera"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ImageSource.gallery),
            child: const Text("Galeri"),
          ),
        ],
      ),
    );

    if (source != null) {
      XFile? pickedFile = await picker.pickImage(source: source, imageQuality: 80);
      if (pickedFile != null) {
        String path = pickedFile.path;
        var request = http.MultipartRequest(
            'POST',
            Uri.parse('http://127.0.0.1:5000/devices/${widget.deviceId}/upload'));
        request.fields['index'] = index.toString();
        request.files.add(await http.MultipartFile.fromPath('file', path));
        
        var response = await request.send();

        if (response.statusCode == 200) {
          fetchDeviceDetails();
        } else {
          // Handle error appropriately
        }
      }
    }
  }

  Widget buildImage(int index) {
    final path = device['resim$index'];
    final fullUrl = path != null ? 'http://127.0.0.1:5000/$path' : null;
    final isCompleted = device['geri_teslim_tarihi'] != null && device['geri_teslim_tarihi'] != '';

    return GestureDetector(
      onTap: isCompleted ? null : () => pickImage(index), // Eðer tamamlandýysa týklanamaz yap
      child: Container(
        width: 100,
        height: 100,
        color: Colors.grey[300],
        child: fullUrl != null
            ? Image.network(fullUrl, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) {
              return const Center(child: Text("Resim yüklenemedi"));
            })
            : Center(child: Text("Resim $index")),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text("Cihaz Detay")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final isCompleted = device['geri_teslim_tarihi'] != null && device['geri_teslim_tarihi'] != '';
    return Scaffold(
      appBar: AppBar(
        title: Text("${device['marka']} ${device['model']}"),
        actions: isCompleted ? [] : [ // Eðer tamamlandýysa butonlarý gizle
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EditDeviceForm(
                    device: device,
                    onSaved: fetchDeviceDetails,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text("Ýþlemi Tamamla"),
                  content: const Text("Bu cihazýn servis iþlemini tamamlamak istediðinize emin misiniz?"),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text("Hayýr"),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text("Evet"),
                    ),
                  ],
                ),
              ) ?? false;
              if (confirmed) {
                await http.put(
                  Uri.parse("http://127.0.0.1:5000/devices/${device['id']}"),
                  headers: {"Content-Type": "application/json"},
                  body: json.encode({
                    "geri_teslim_tarihi": DateTime.now().toIso8601String().split('T').first,
                  }),
                );
                fetchDeviceDetails();
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            Text("Seri No: ${device['seri_no']}"),
            Text("Kurum: ${device['kurum']}"),
            Text("Alýnma Tarihi: ${device['alinma_tarihi']}"),
            Text("Aksesuar: ${device['aksesuar']}"),
            Text("Arýza: ${device['ariza']}"),
            Text("Servis Tespiti: ${device['tespit']}"),
            Text("Geri Teslim Tarihi: ${device['geri_teslim_tarihi'] ?? '-'}"),
            Text("Ýlgili Personel: ${device['personel'] ?? '-'}"),
            Text("Maliyet: ${device['maliyet']}"),
            Text("Servis Ücreti: ${device['servis_ucreti']}"),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                buildImage(1),
                buildImage(2),
                buildImage(3),
              ],
            )
          ],
        ),
      ),
    );
  }
}

// ---------------- Edit Device Form ----------------
class EditDeviceForm extends StatefulWidget {
  final Map device;
  final VoidCallback onSaved;
  EditDeviceForm({super.key, required this.device, required this.onSaved});

  @override
  State<EditDeviceForm> createState() => _EditDeviceFormState();
}

class _EditDeviceFormState extends State<EditDeviceForm> {
  final _formKey = GlobalKey<FormState>();
  late Map<String, dynamic> formData;
  final Map<String, TextEditingController> controllers = {};

  @override
  void initState() {
    super.initState();
    formData = Map.from(widget.device);
    formData.forEach((key, value) {
      controllers[key] = TextEditingController(text: value?.toString());
    });
  }

  Future<void> updateDevice() async {
    final response = await http.put(
      Uri.parse("http://127.0.0.1:5000/devices/${formData['id']}"),
      headers: {"Content-Type": "application/json"},
      body: json.encode(formData),
    );
    if (response.statusCode == 200) {
      widget.onSaved();
      Navigator.pop(context);
    }
  }

  Widget buildTextField(String label, String key) {
    return TextFormField(
      controller: controllers[key],
      decoration: InputDecoration(labelText: label),
      onChanged: (value) => formData[key] = value,
    );
  }

  Widget buildDatePickerField(String label, String key) {
    return InkWell(
      onTap: () async {
        DateTime? pickedDate = await showDatePicker(
          context: context,
          initialDate: DateTime.tryParse(formData[key] ?? '') ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (pickedDate != null) {
          String formattedDate =
              "${pickedDate.year}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.day.toString().padLeft(2, '0')}";
          setState(() {
            formData[key] = formattedDate;
            controllers[key]!.text = formattedDate;
          });
        }
      },
      child: IgnorePointer(
        child: TextFormField(
          controller: controllers[key],
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: const Icon(Icons.calendar_today),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              buildTextField("Maliyet", "maliyet"),
              buildTextField("Servis Ücreti", "servis_ucreti"),
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

  @override
  void dispose() {
    controllers.forEach((key, controller) => controller.dispose());
    super.dispose();
  }
}